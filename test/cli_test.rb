require "test_helper"
require "tmpdir"
require "stringio"

class CLITest < Minitest::Test
  def test_end_to_end_against_fixture_repos_without_github
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.commit(repo, "Add widget", time: Time.now - 3_600)
      RepoFactory.init_repo(File.join(root, "sleepy"))
      out = StringIO.new

      status = Spill::CLI.run([ root, "--no-github" ], stdout: out)

      assert_equal 0, status
      assert_includes out.string, "DONE"
      assert_includes out.string, "proj · main · 1 commit"
      assert_includes out.string, "Add widget"
      assert_includes out.string, "1 quiet repo skipped"
      refute_includes out.string, "\e[" # StringIO is not a TTY: no color
    end
  end

  def test_since_flag_narrows_the_window
    Dir.mktmpdir do |root|
      repo = RepoFactory.init_repo(File.join(root, "proj"))
      RepoFactory.commit(repo, "Ancient", time: Time.now - (10 * 86_400))
      out = StringIO.new

      Spill::CLI.run([ root, "--no-github", "--since", "2 days ago" ], stdout: out)

      assert_includes out.string, "Nothing to spill. 🍵"
    end
  end

  def test_version_flag
    out = StringIO.new

    status = Spill::CLI.run([ "--version" ], stdout: out)

    assert_equal 0, status
    assert_equal "#{Spill::VERSION}\n", out.string
  end

  def test_bad_since_still_exits_zero_with_message
    out = StringIO.new

    status = Spill::CLI.run([ "--no-github", "--since", "the vibes" ], stdout: out)

    assert_equal 0, status
    assert_includes out.string, "spill:"
  end
end
