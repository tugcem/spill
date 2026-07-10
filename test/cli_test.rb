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
      assert_includes out.string, "  proj\n"
      assert_includes out.string, "main · 1 commit"
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

  def test_no_ai_flag_is_accepted_and_never_touches_the_narrator
    Dir.mktmpdir do |root|
      RepoFactory.init_repo(File.join(root, "proj"))
      out = StringIO.new

      with_narrate_spy(raises: true) do
        status = Spill::CLI.run([ root, "--no-github", "--no-ai" ], stdout: out)

        assert_equal 0, status
      end
      refute_includes out.string, "\e[3m"
    end
  end

  def test_stringio_stdout_is_not_a_tty_so_ai_never_runs_even_without_no_ai
    Dir.mktmpdir do |root|
      RepoFactory.init_repo(File.join(root, "proj"))
      out = StringIO.new

      with_narrate_spy(raises: true) do
        status = Spill::CLI.run([ root, "--no-github" ], stdout: out)

        assert_equal 0, status
      end
      refute_includes out.string, "\e[3m"
    end
  end

  def test_ai_summary_drops_only_the_repo_whose_block_failed
    t = Time.new(2026, 7, 3, 10)
    window = Spill::Window.new(since: Time.new(2026, 7, 3), label: "today + yesterday")
    report = Spill::Report.build(
      local: [
        Spill::Event.new(source: :local_git, kind: :commit, repo: "newer",
                         title: "Ship it", ref: "main", timestamp: t + 60),
        Spill::Event.new(source: :local_git, kind: :commit, repo: "older",
                         title: "Fix it", ref: "main", timestamp: t)
      ],
      github: [], repos: %w[newer older], window: window
    )

    with_narrate_returning([ "Shipped it.", nil ]) do
      assert_equal [ [ "newer", "Shipped it." ] ], Spill::CLI.ai_summary(report)
    end
  end

  def test_ai_summary_swallows_narrator_layer_errors
    window = Spill::Window.new(since: Time.new(2026, 7, 3), label: "today + yesterday")
    report = Spill::Report.build(
      local: [
        Spill::Event.new(source: :local_git, kind: :commit, repo: "proj",
                         title: "Ship it", ref: "main", timestamp: Time.new(2026, 7, 3, 10))
      ],
      github: [], repos: %w[proj], window: window
    )

    with_narrate_returning(->(*) { raise "model exploded" }) do
      assert_nil Spill::CLI.ai_summary(report)
    end
  end

  private

  def with_narrate_returning(result)
    original = Spill::Narrator.method(:narrate)
    silence_warnings do
      Spill::Narrator.define_singleton_method(:narrate) do |*args, **kwargs|
        result.respond_to?(:call) ? result.call(*args, **kwargs) : result
      end
    end
    yield
  ensure
    silence_warnings { Spill::Narrator.define_singleton_method(:narrate, original) }
  end

  # Temporarily replaces Spill::Narrator.narrate with a spy that raises if called,
  # proving the tty/--no-ai gates keep it from ever running under StringIO.
  def with_narrate_spy(raises:)
    original = Spill::Narrator.method(:narrate)
    silence_warnings do
      Spill::Narrator.define_singleton_method(:narrate) do |*_args, **_kwargs|
        raise "Narrator.narrate should not be called" if raises
      end
    end
    yield
  ensure
    silence_warnings { Spill::Narrator.define_singleton_method(:narrate, original) }
  end

  def silence_warnings
    original_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original_verbose
  end
end
