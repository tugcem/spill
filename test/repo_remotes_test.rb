require "test_helper"
require "tmpdir"

class RepoRemotesTest < Minitest::Test
  def test_ssh_url_parses_to_slug
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "git@github.com:acme/proj.git")

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_equal Set["acme/proj"], slugs
    end
  end

  def test_https_url_with_dot_git_parses_to_slug
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "https://github.com/acme/proj.git")

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_equal Set["acme/proj"], slugs
    end
  end

  def test_https_url_without_dot_git_parses_to_slug
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "https://github.com/acme/proj")

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_equal Set["acme/proj"], slugs
    end
  end

  def test_repo_with_no_remote_is_excluded
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_empty slugs
    end
  end

  def test_non_github_remote_is_excluded
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "https://gitlab.com/acme/proj.git")

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_empty slugs
    end
  end
end
