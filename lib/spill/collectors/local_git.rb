require "open3"
require "time"

module Spill
  module Collectors
    class LocalGit
      SEP = "\x1f"

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
                    "--pretty=format:%H#{SEP}%ad#{SEP}%s")
          next [] if log.nil?

          log.each_line(chomp: true).filter_map do |line|
            sha, date, subject = line.split(SEP, 3)
            next if sha.nil? || seen[sha]

            seen[sha] = true
            Event.new(source: :local_git, kind: :commit, repo: name, title: subject,
                      ref: branch, timestamp: Time.parse(date), extra: { sha: sha })
          end
        end
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
