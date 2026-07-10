require "open3"
require "time"

module Spill
  module Collectors
    class LocalGit
      SEP = "\x1f"
      RECORD_SEP = "\x1e"

      def initialize(repo_paths:, author: nil)
        @repo_paths = repo_paths
        @author = author
      end

      def collect(window:)
        @repo_paths.flat_map { |path| repo_events(path, window) }
      end

      private

      def repo_events(path, window)
        name = File.basename(path)
        events = []
        email = @author || git(path, "config", "user.email")&.strip
        events.concat(commit_events(path, name, email, window)) unless email.nil? || email.empty?
        events.concat(state_events(path, name))
        events
      end

      def commit_events(path, name, email, window)
        seen = {}
        ordered_branches(path).flat_map do |branch|
          log = git(path, "log", branch, "--no-merges", "--author=#{email}",
                    "--since=#{window.since.iso8601}", "--date=iso-strict",
                    "--pretty=format:%H#{SEP}%ad#{SEP}%s#{SEP}%b#{RECORD_SEP}")
          next [] if log.nil?

          log.split(RECORD_SEP).filter_map do |record|
            sha, date, subject, body = record.strip.split(SEP, 4)
            # SHA-1 or SHA-256 repos; a body containing our separators makes
            # a malformed record, not a forged commit — skip, never raise.
            next unless sha&.match?(/\A(?:\h{40}|\h{64})\z/)
            next if seen[sha]

            timestamp = begin
              Time.parse(date)
            rescue ArgumentError, TypeError
              next
            end
            seen[sha] = true
            Event.new(source: :local_git, kind: :commit, repo: name, title: subject,
                      ref: branch, timestamp: timestamp,
                      extra: { sha: sha, body: clean_body(body) })
          end
        end
      end

      # Trailers (Co-Authored-By:, Signed-off-by:, ...) are metadata, not
      # prose — drop the final paragraph when every line in it is
      # trailer-shaped.
      def clean_body(body)
        paragraphs = body.to_s.strip.split(/\n{2,}/)
        paragraphs.pop if paragraphs.any? && paragraphs.last.lines.all? { |l| l.match?(/\A[\w-]+:\s/) }
        text = paragraphs.join("\n\n").strip
        text.empty? ? nil : text
      end

      def state_events(path, name)
        events = []
        dirty = (git(path, "status", "--porcelain") || "").lines.count
        if dirty.positive?
          events << Event.new(source: :local_git, kind: :dirty_tree, repo: name,
                              extra: { files: dirty })
        end
        events.concat(unpushed_events(path, name))
        events
      end

      def unpushed_events(path, name)
        return [] if (git(path, "remote") || "").strip.empty?

        refs = git(path, "for-each-ref", "refs/heads",
                   "--format=%(refname:short)#{SEP}%(upstream:short)#{SEP}%(upstream:track)")
        (refs || "").each_line(chomp: true).filter_map do |line|
          branch, upstream, track = line.split(SEP, 3)
          if upstream.nil? || upstream.empty?
            count = git(path, "rev-list", "--count", branch, "--not", "--remotes").to_i
            next unless count.positive?

            Event.new(source: :local_git, kind: :branch_wip, repo: name, ref: branch,
                      extra: { unpushed: count, no_upstream: true })
          elsif track =~ /ahead (\d+)/
            Event.new(source: :local_git, kind: :branch_wip, repo: name, ref: branch,
                      extra: { ahead: Regexp.last_match(1).to_i })
          end
        end
      end

      def ordered_branches(path)
        head = git(path, "symbolic-ref", "--short", "HEAD")&.strip
        all = (git(path, "for-each-ref", "refs/heads", "--format=%(refname:short)") || "")
              .each_line(chomp: true).to_a
        ([ head ] + (all - [ head ]).sort).compact.uniq
      end

      def git(path, *args)
        out, _err, status = Open3.capture3("git", "-C", path, *args)
        status.success? ? out : nil
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
