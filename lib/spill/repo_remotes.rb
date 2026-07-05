require "set"
require "open3"

module Spill
  module RepoRemotes
    SSH_PATTERN = %r{\Agit@github\.com:(?<slug>.+?)(?:\.git)?/?\z}
    SSH_PROTOCOL_PATTERN = %r{\Assh://git@github\.com/(?<slug>.+?)(?:\.git)?/?\z}
    HTTPS_PATTERN = %r{\Ahttps://github\.com/(?<slug>.+?)(?:\.git)?/?\z}

    def self.github_slugs(repo_paths)
      slug_map(repo_paths).keys.to_set
    end

    def self.slug_map(repo_paths)
      repo_paths.each_with_object({}) do |path, map|
        slug = slug_for(path)
        map[slug] = File.basename(path) if slug
      end
    end

    def self.slug_for(path)
      url = origin_url(path)
      return nil if url.nil?

      match = SSH_PATTERN.match(url) || SSH_PROTOCOL_PATTERN.match(url) || HTTPS_PATTERN.match(url)
      match && match[:slug].downcase
    end

    def self.origin_url(path)
      out, _err, status = Open3.capture3("git", "-C", path, "remote", "get-url", "origin")
      status.success? ? out.strip : nil
    rescue Errno::ENOENT
      nil
    end
  end
end
