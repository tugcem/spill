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
        email = @author || git(path, "config", "user.email")&.strip
        return [] if email.nil? || email.empty?

        commit_events(path, name, email, window)
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
