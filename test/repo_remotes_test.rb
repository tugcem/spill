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

  def test_ssh_protocol_url_parses_to_slug
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "ssh://git@github.com/acme/proj.git")

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_equal Set["acme/proj"], slugs
    end
  end

  def test_mixed_case_url_downcases_to_slug
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "https://github.com/Acme/Proj.git")

      slugs = Spill::RepoRemotes.github_slugs([ repo ])

      assert_equal Set["acme/proj"], slugs
    end
  end

  def test_trailing_slash_url_parses_clean
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "https://github.com/acme/proj/")

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

  def test_slug_map_maps_downcased_slug_to_local_basename
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.git(repo, "remote", "add", "origin", "git@github.com:Acme/Proj.git")

      map = Spill::RepoRemotes.slug_map([ repo ])

      assert_equal({ "acme/proj" => "proj" }, map)
    end
  end

  def test_slug_map_excludes_repos_with_no_github_remote
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))

      map = Spill::RepoRemotes.slug_map([ repo ])

      assert_empty map
    end
  end
end
