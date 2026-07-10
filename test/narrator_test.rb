require "test_helper"
require "tmpdir"
require "fileutils"

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

  def test_compile_renames_temp_into_place_and_leaves_no_temp_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "narrator")
      fake_swiftc = lambda do |tmp|
        File.write(tmp, "binary contents")
        true
      end

      with_stubbed_narrator_method(:swiftc, fake_swiftc) do
        assert Spill::Narrator.compile(path)
      end

      assert_equal "binary contents", File.read(path)
      assert_empty Dir.glob("#{path}.tmp*"), "expected the temp compile file to be renamed away"
    end
  end

  def test_failed_compile_writes_marker_and_is_not_retried
    Dir.mktmpdir do |cache_dir|
      with_env("XDG_CACHE_HOME" => cache_dir) do
        calls = 0
        failing_swiftc = lambda do |_tmp|
          calls += 1
          false
        end

        with_stubbed_narrator_method(:swiftc, failing_swiftc) do
          assert_nil Spill::Narrator.compiled_binary
          assert_nil Spill::Narrator.compiled_binary
        end

        assert_equal 1, calls, "expected the failure marker to prevent a recompile"
        assert File.exist?("#{Spill::Narrator.cache_path}.failed")
      end
    end
  end

  def test_successful_compile_clears_a_stale_failure_marker
    Dir.mktmpdir do |dir|
      path = File.join(dir, "narrator")
      FileUtils.touch("#{path}.failed")
      fake_swiftc = lambda do |tmp|
        File.write(tmp, "binary contents")
        true
      end

      with_stubbed_narrator_method(:swiftc, fake_swiftc) do
        assert Spill::Narrator.compile(path)
      end

      refute File.exist?("#{path}.failed"), "expected a successful compile to clear the failure marker"
    end
  end

  def test_swiftc_kills_a_hung_compiler_at_the_timeout
    Dir.mktmpdir do |dir|
      tmp = File.join(dir, "out")
      with_stubbed_narrator_method(:compile_command, ->(_tmp) { [ "sleep", "5" ] }) do
        start = Time.now
        result = Spill::Narrator.swiftc(tmp, timeout: 0.2)
        elapsed = Time.now - start

        assert_equal false, result
        assert elapsed < 4, "expected the compiler to be killed instead of waited out (took #{elapsed}s)"
      end
    end
  end

  def test_narrate_deletes_a_corrupt_cached_binary
    Dir.mktmpdir do |cache_dir|
      with_env("XDG_CACHE_HOME" => cache_dir) do
        path = Spill::Narrator.cache_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "not a real binary")
        File.chmod(0o755, path)
        FileUtils.touch("#{path}.failed")

        # Exec of a corrupt binary raises platform-dependently (ENOEXEC on
        # Linux, EBADMACHO on macOS), so raise it deterministically here.
        raise_exec_error = ->(*) { raise Errno::ENOEXEC }
        with_stubbed_narrator_method(:run, raise_exec_error) do
          assert_nil Spill::Narrator.narrate("hello")
        end

        refute File.exist?(path), "expected the corrupt cached binary to be removed"
        refute File.exist?("#{path}.failed"), "expected the failure marker to be removed with the binary"
      end
    end
  end

  private

  # Minitest 6 dropped minitest/mock, so swap the module's singleton method
  # by hand and restore it after.
  def with_stubbed_narrator_method(name, replacement)
    mod = Spill::Narrator
    original = mod.method(name)
    mod.singleton_class.send(:remove_method, name)
    mod.singleton_class.send(:define_method, name) do |*args, **kwargs, &block|
      replacement.call(*args, **kwargs, &block)
    end
    yield
  ensure
    mod.singleton_class.send(:remove_method, name)
    mod.singleton_class.send(:define_method, name, original)
  end

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
