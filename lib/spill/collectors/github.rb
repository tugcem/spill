require "json"
require "open3"
require "time"

module Spill
  module Collectors
    class Github
      MAX_PAGES = 3
      PAGE_SIZE = 100
      SEARCH_PAGE_SIZE = 100
      # An open PR is shown in Doing only if created in-window or up to 14 days before it.
      OPEN_PR_GRACE_SECONDS = 14 * 86_400

      DEFAULT_RUNNER = lambda do |args|
        out, _err, status = Open3.capture3("gh", *args)
        [ out, status.success? ]
      rescue Errno::ENOENT
        [ "", false ]
      end

      def initialize(runner: DEFAULT_RUNNER)
        @runner = runner
      end

      def collect(window:, scope: nil)
        login = fetch_login
        return nil if login.nil?

        raw = fetch_raw_events(login)
        return nil if raw.nil?

        events = raw.filter_map { |item| map_event(item) }
                    .select { |event| event.timestamp >= window.since }
        events = dedupe_commented(events)

        open_prs = open_pr_events(login, window)
        return nil if open_prs.nil?

        merged_prs = merged_pr_events(login, window)
        return nil if merged_prs.nil?

        opened_prs = opened_pr_events(login, window)
        return nil if opened_prs.nil?

        events.concat(open_prs)
        events.concat(merged_prs)
        events.concat(opened_prs)
        events = dedupe_search_capped(events)
        events << truncation_event(raw) if truncated?(raw, window)
        events = apply_scope(events, scope) unless scope.nil?
        events
      rescue StandardError
        nil
      end

      private

      SCOPE_EXEMPT_KINDS = %i[ starred github_truncated github_search_capped ].freeze

      def apply_scope(events, scope)
        events.select do |event|
          SCOPE_EXEMPT_KINDS.include?(event.kind) || scope.include?(event.repo.to_s.downcase)
        end
      end

      def fetch_login
        out, ok = @runner.call([ "api", "user" ])
        return nil unless ok

        JSON.parse(out)["login"]
      rescue JSON::ParserError
        nil
      end

      def fetch_raw_events(login)
        raw = []
        (1..MAX_PAGES).each do |page|
          out, ok = @runner.call([ "api", "users/#{login}/events?per_page=#{PAGE_SIZE}&page=#{page}" ])
          return nil unless ok

          batch = JSON.parse(out)
          raw.concat(batch)
          break if batch.size < PAGE_SIZE
        end
        raw
      rescue JSON::ParserError
        nil
      end

      def map_event(item)
        repo = item.dig("repo", "name")
        created = item["created_at"]
        return nil if created.nil?

        time = Time.parse(created).localtime
        case item["type"]
        when "PullRequestReviewEvent" then build(:review, item.dig("payload", "pull_request"), repo, time)
        when "IssuesEvent"
          build(:issue_closed, item.dig("payload", "issue"), repo, time) if item.dig("payload", "action") == "closed"
        when "IssueCommentEvent"
          build(:commented, item.dig("payload", "issue"), repo, time) if item.dig("payload", "action") == "created"
        when "PullRequestReviewCommentEvent"
          if item.dig("payload", "action") == "created"
            build(:commented, item.dig("payload", "pull_request"), repo, time)
          end
        when "WatchEvent"
          Event.new(source: :github, kind: :starred, repo: repo, timestamp: time) if item.dig("payload", "action") == "started"
        end
      end

      def dedupe_commented(events)
        commented, other = events.partition { |event| event.kind == :commented }
        deduped = commented.group_by { |event| [ event.repo, event.ref ] }
                           .map { |_key, group| group.max_by(&:timestamp) }
        other + deduped
      end

      def build(kind, subject, repo, time)
        return nil if subject.nil?

        Event.new(source: :github, kind: kind, repo: repo, title: subject["title"],
                  ref: "##{subject["number"]}", timestamp: time)
      end

      def open_pr_events(login, window)
        query = "search/issues?q=is:pr+is:open+author:#{login}&per_page=#{SEARCH_PAGE_SIZE}&advanced_search=true"
        out, ok = @runner.call([ "api", query ])
        return nil unless ok

        items = JSON.parse(out).fetch("items", [])
        cutoff = window.since - OPEN_PR_GRACE_SECONDS
        events = items.filter_map do |item|
          next if item["created_at"].nil?

          opened_at = Time.parse(item["created_at"]).localtime
          next if opened_at < cutoff

          Event.new(source: :github, kind: :pr_open,
                    repo: item["repository_url"].to_s.split("/repos/").last,
                    title: item["title"], ref: "##{item["number"]}",
                    timestamp: Time.parse(item["updated_at"]).localtime, extra: { opened_at: opened_at })
        end
        events << search_cap_event(items)
        events.compact
      rescue JSON::ParserError
        nil
      end

      def merged_pr_events(login, window)
        since = window.since.strftime("%Y-%m-%d")
        query = "search/issues?q=is:pr+author:#{login}+merged:%3E=#{since}&per_page=#{SEARCH_PAGE_SIZE}&advanced_search=true"
        out, ok = @runner.call([ "api", query ])
        return nil unless ok

        items = JSON.parse(out).fetch("items", [])
        events = items.filter_map do |item|
          merged_at = item.dig("pull_request", "merged_at") || item["closed_at"]
          next if merged_at.nil?

          time = Time.parse(merged_at).localtime
          next if time < window.since

          Event.new(source: :github, kind: :pr_merged,
                    repo: item["repository_url"].to_s.split("/repos/").last,
                    title: item["title"], ref: "##{item["number"]}", timestamp: time)
        end
        events << search_cap_event(items)
        events.compact
      rescue JSON::ParserError
        nil
      end

      def opened_pr_events(login, window)
        since = window.since.strftime("%Y-%m-%d")
        query = "search/issues?q=is:pr+author:#{login}+created:%3E=#{since}&per_page=#{SEARCH_PAGE_SIZE}&advanced_search=true"
        out, ok = @runner.call([ "api", query ])
        return nil unless ok

        items = JSON.parse(out).fetch("items", [])
        events = items.filter_map do |item|
          time = Time.parse(item["created_at"]).localtime
          next if time < window.since

          Event.new(source: :github, kind: :pr_opened,
                    repo: item["repository_url"].to_s.split("/repos/").last,
                    title: item["title"], ref: "##{item["number"]}", timestamp: time)
        end
        events << search_cap_event(items)
        events.compact
      rescue JSON::ParserError
        nil
      end

      # Search results are relevance-sorted, so a capped page has no chronological
      # boundary — the cap event carries no date, unlike :github_truncated.
      def search_cap_event(items)
        return nil unless items.size == SEARCH_PAGE_SIZE

        Event.new(source: :github, kind: :github_search_capped, repo: nil)
      end

      def dedupe_search_capped(events)
        capped, rest = events.partition { |event| event.kind == :github_search_capped }
        capped.empty? ? rest : rest << capped.first
      end

      def truncated?(raw, window)
        return false if raw.size < MAX_PAGES * PAGE_SIZE

        oldest_time(raw) > window.since
      end

      def truncation_event(raw)
        Event.new(source: :github, kind: :github_truncated, repo: nil,
                  extra: { oldest: oldest_time(raw) })
      end

      def oldest_time(raw)
        raw.map { |item| Time.parse(item["created_at"]) }.min.localtime
      end
    end
  end
end
