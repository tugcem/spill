require "test_helper"
require "tmpdir"
require "fileutils"

class RepoFinderTest < Minitest::Test
  def test_finds_repos_at_root_one_and_two_levels_deep
    Dir.mktmpdir do |root|
      RepoFactory.init_repo(File.join(root, "level1"))
      RepoFactory.init_repo(File.join(root, "group", "level2"))
      FileUtils.mkdir_p(File.join(root, "not-a-repo"))

      found = Spill::RepoFinder.find(root)

      assert_equal [ File.join(root, "group", "level2"), File.join(root, "level1") ].sort, found
    end
  end

  def test_root_itself_being_a_repo_is_included
    Dir.mktmpdir do |root|
      RepoFactory.init_repo(root)

      assert_equal [ root ], Spill::RepoFinder.find(root)
    end
  end

  def test_empty_root_finds_nothing
    Dir.mktmpdir do |root|
      assert_empty Spill::RepoFinder.find(root)
    end
  end
end
