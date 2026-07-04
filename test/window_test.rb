require "test_helper"

class WindowTest < Minitest::Test
  NOW = Time.new(2026, 7, 4, 15, 30, 0)

  def test_default_window_starts_at_midnight_yesterday
    window = Spill::Window.default(now: NOW)

    assert_equal Time.new(2026, 7, 3, 0, 0, 0), window.since
    assert_equal "today + yesterday", window.label
  end

  def test_parse_days_ago
    window = Spill::Window.parse("3 days ago", now: NOW)

    assert_equal NOW - (3 * 86_400), window.since
    assert_equal "3 days ago", window.label
  end

  def test_parse_hours_and_weeks
    assert_equal NOW - 7_200, Spill::Window.parse("2 hours ago", now: NOW).since
    assert_equal NOW - (2 * 7 * 86_400), Spill::Window.parse("2 weeks ago", now: NOW).since
  end

  def test_parse_yesterday_and_today
    assert_equal Time.new(2026, 7, 3, 0, 0, 0), Spill::Window.parse("yesterday", now: NOW).since
    assert_equal Time.new(2026, 7, 4, 0, 0, 0), Spill::Window.parse("today", now: NOW).since
  end

  def test_parse_iso_date
    assert_equal Time.new(2026, 7, 1, 0, 0, 0), Spill::Window.parse("2026-07-01", now: NOW).since
  end

  def test_parse_garbage_raises
    assert_raises(ArgumentError) { Spill::Window.parse("the vibes", now: NOW) }
  end
end
