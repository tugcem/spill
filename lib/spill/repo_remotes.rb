require "set"
require "open3"

module Spill
  module RepoRemotes
    SSH_PATTERN = %r{\Agit@github\.com:(?<slug>.+?)(?:\.git)?\z}
    HTTPS_PATTERN = %r{\Ahttps://github\.com/(?<slug>.+?)(?:\.git)?\z}

    def self.github_slugs(repo_paths)
      repo_paths.filter_map { |path| slug_for(path) }.to_set
    end

    def self.slug_for(path)
      url = origin_url(path)
      return nil if url.nil?

      match = SSH_PATTERN.match(url) || HTTPS_PATTERN.match(url)
      match && match[:slug]
    end

    def self.origin_url(path)
      out, _err, status = Open3.capture3("git", "-C", path, "remote", "get-url", "origin")
      status.success? ? out.strip : nil
    rescue Errno::ENOENT
      nil
    end
  end
end
