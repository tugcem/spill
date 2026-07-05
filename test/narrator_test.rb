require "test_helper"
require "tmpdir"

class NarratorTest < Minitest::Test
  def test_available_matches_darwin_platform
    assert_equal RUBY_PLATFORM.include?("darwin"), Spill::Narrator.available?
  end

  def test_narrate_returns_nil_when_binary_path_does_not_exist_and_compile_fails
    Dir.mktmpdir do |cache_dir|
      with_env("XDG_CACHE_HOME" => cache_dir, "PATH" => "/nonexistent-bin") do
        result = Spill::Narrator.narrate("hello", binary: nil)

        assert_nil result
      end
    end
  end

  def test_narrate_happy_path_returns_stripped_output_of_fake_binary
    with_fake_binary("#!/bin/sh\ncat\n") do |bin|
      result = Spill::Narrator.narrate("hello world\n", binary: bin)

      assert_equal "hello world", result
    end
  end

  def test_narrate_returns_nil_and_kills_process_on_timeout
    with_fake_binary("#!/bin/sh\nsleep 5\necho done\n") do |bin|
      start = Time.now
      result = Spill::Narrator.narrate("hello", timeout: 0.2, binary: bin)
      elapsed = Time.now - start

      assert_nil result
      assert elapsed < 4, "expected the process to be killed instead of waited out (took #{elapsed}s)"
    end
  end

  def test_narrate_returns_nil_on_nonzero_exit
    with_fake_binary("#!/bin/sh\necho unavailable 1>&2\nexit 2\n") do |bin|
      result = Spill::Narrator.narrate("hello", binary: bin)

      assert_nil result
    end
  end

  def test_narrate_returns_nil_on_blank_output
    with_fake_binary("#!/bin/sh\ncat > /dev/null\necho ''\n") do |bin|
      result = Spill::Narrator.narrate("hello", binary: bin)

      assert_nil result
    end
  end

  private

  def with_fake_binary(script)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "fake-narrator")
      File.write(path, script)
      File.chmod(0o755, path)
      yield path
    end
  end

  def with_env(vars)
    original = vars.keys.to_h { |key| [ key, ENV[key] ] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
