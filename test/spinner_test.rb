require "test_helper"
require "stringio"

class SpinnerTest < Minitest::Test
  def test_disabled_runs_block_returns_value_and_writes_nothing
    out = StringIO.new

    result = Spill::Spinner.around(enabled: false, out: out) { 42 }

    assert_equal 42, result
    assert_equal "", out.string
  end

  def test_enabled_writes_frames_and_clears_the_line_at_the_end
    out = StringIO.new

    result = Spill::Spinner.around(enabled: true, out: out) do
      sleep 0.35
      "done"
    end

    assert_equal "done", result
    assert_operator out.string.length, :>, 0
    assert Spill::Spinner::FRAMES.any? { |frame| out.string.include?(frame) }
    assert out.string.end_with?("\r\e[K"), "expected output to end with a cleared line, got: #{out.string.inspect}"
  end

  def test_enabled_clears_the_line_and_reraises_on_exception
    out = StringIO.new

    error = assert_raises(RuntimeError) do
      Spill::Spinner.around(enabled: true, out: out) do
        sleep 0.2
        raise "boom"
      end
    end

    assert_equal "boom", error.message
    assert out.string.end_with?("\r\e[K"), "expected output to end with a cleared line, got: #{out.string.inspect}"
  end
end
