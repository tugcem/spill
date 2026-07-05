module Spill
  Report = Data.define(:window, :done, :doing, :quiet, :explored, :notes) do
    GITHUB_DONE_KINDS = %i[ pr_opened pr_merged review issue_closed commented ].freeze
    LOCAL_STATE_KINDS = %i[ branch_wip dirty_tree ].freeze

    def self.build(local:, github:, repos:, window:, repo_map: {})
      local ||= []
      github_events = github || []
      commits = local.select { |event| event.kind == :commit }
      state = local.select { |event| LOCAL_STATE_KINDS.include?(event.kind) }
      done_github = collapse_opened_and_merged(
        github_events.select { |e| GITHUB_DONE_KINDS.include?(e.kind) }
      )

      done = build_done(commits, done_github, repo_map)
      doing = build_doing(state, github_events, repo_map)

      new(
        window: window,
        done: done,
        doing: doing,
        quiet: repos - (done.map { |g| g[:repo] } + doing.map { |g| g[:repo] }).uniq,
        explored: build_explored(github_events),
        notes: build_notes(github, github_events)
      )
    end

    def self.collapse_opened_and_merged(events)
      opened_keys = events.select { |e| e.kind == :pr_opened }.map { |e| [ e.repo, e.ref ] }
      merged_keys = events.select { |e| e.kind == :pr_merged }.map { |e| [ e.repo, e.ref ] }
      paired = (opened_keys & merged_keys).uniq

      survivors = events.reject do |e|
        %i[pr_opened pr_merged].include?(e.kind) && paired.include?([ e.repo, e.ref ])
      end

      collapsed = paired.map do |repo, ref|
        merged = events.find { |e| e.kind == :pr_merged && e.repo == repo && e.ref == ref }
        Event.new(source: :github, kind: :pr_opened_and_merged, repo: merged.repo,
                  title: merged.title, ref: merged.ref, timestamp: merged.timestamp)
      end

      survivors + collapsed
    end

    def self.build_done(commits, done_github, repo_map)
      groups = {}

      commits.group_by(&:repo).each do |repo, events|
        branches = events.group_by(&:ref).map do |branch, list|
          { name: branch, commits: list.sort_by(&:timestamp) }
        end
        groups[repo] = { repo: repo, branches: branches, github: [], last: events.map(&:timestamp).max }
      end

      done_github.group_by { |e| repo_map[e.repo.to_s.downcase] || e.repo }.each do |name, events|
        sorted = events.sort_by(&:timestamp)
        if groups[name]
          groups[name][:github] = sorted
          groups[name][:last] = [ groups[name][:last], sorted.map(&:timestamp).max ].max
        else
          groups[name] = { repo: name, branches: [], github: sorted, last: sorted.map(&:timestamp).max }
        end
      end

      groups.values.sort_by { |g| g[:last] }.reverse
    end

    def self.build_doing(state, github_events, repo_map)
      open_prs = github_events.select { |e| e.kind == :pr_open }
      groups = {}

      state.group_by(&:repo).each { |repo, events| groups[repo] = { repo: repo, items: events } }

      open_prs.group_by { |e| repo_map[e.repo.to_s.downcase] || e.repo }.each do |name, events|
        groups[name] ||= { repo: name, items: [] }
        groups[name][:items] += events
      end

      groups.each_value { |g| g[:items] = g[:items].sort_by { |e| doing_sort_key(e) } }
      groups.values.sort_by { |g| g[:repo] }
    end

    def self.doing_sort_key(event)
      case event.kind
      when :dirty_tree then [ 0, "", 0.0 ]
      when :branch_wip then [ 1, event.ref.to_s, 0.0 ]
      when :pr_open then [ 2, "", -event.timestamp.to_f ]
      end
    end

    def self.build_explored(github_events)
      github_events.select { |e| e.kind == :starred }
                   .group_by(&:repo)
                   .map { |repo, events| [ repo, events.map(&:timestamp).max ] }
                   .sort_by { |_repo, time| time }
                   .reverse
                   .map(&:first)
    end

    def self.build_notes(github, github_events)
      notes = []
      notes << "GitHub: skipped (gh not available)" if github.nil?
      truncated = github_events.find { |e| e.kind == :github_truncated }
      notes << "GitHub: may be incomplete before #{truncated.extra[:oldest].strftime("%b %-d")}" if truncated
      if github_events.any? { |e| e.kind == :github_search_capped }
        notes << "GitHub: search results may be incomplete (capped at 100)"
      end
      notes
    end
  end
end
