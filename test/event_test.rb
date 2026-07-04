require "test_helper"

class EventTest < Minitest::Test
  def test_builds_with_only_required_fields
    event = Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "spill")

    assert_equal :local_git, event.source
    assert_equal :dirty_tree, event.kind
    assert_equal "spill", event.repo
    assert_nil event.title
    assert_nil event.ref
    assert_nil event.timestamp
    assert_equal({}, event.extra)
  end

  def test_carries_optional_fields
    time = Time.new(2026, 7, 3, 14, 0, 0)
    event = Spill::Event.new(source: :github, kind: :pr_merged, repo: "tugcem/spill",
                             title: "Add QR page", ref: "#12", timestamp: time,
                             extra: { url: "x" })

    assert_equal "#12", event.ref
    assert_equal time, event.timestamp
    assert_equal "x", event.extra[:url]
  end
end
