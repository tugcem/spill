require "test_helper"

class ReportTest < Minitest::Test
  WINDOW = Spill::Window.new(since: Time.new(2026, 7, 3), label: "today + yesterday")

  def test_buckets_commits_by_repo_and_branch_most_recent_repo_first
    t = Time.new(2026, 7, 3, 10, 0, 0)
    local = [
      commit("sleepy", "Old fix", "main", t),
      commit("busy", "First", "main", t + 3_600),
      commit("busy", "Second", "main", t + 7_200),
      commit("busy", "Branch work", "feature", t + 1_800)
    ]

    report = build(local: local, repos: %w[busy sleepy quiet])

    assert_equal %w[busy sleepy], report.done.map { |entry| entry[:repo] }
    busy_main = report.done.first[:branches].find { |b| b[:name] == "main" }
    assert_equal [ "First", "Second" ], busy_main[:commits].map(&:title)
    assert_equal [ "quiet" ], report.quiet
  end

  def test_doing_collects_state_then_open_prs
    local = [
      Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "busy", extra: { files: 2 }),
      Spill::Event.new(source: :local_git, kind: :branch_wip, repo: "app", ref: "wip", extra: { ahead: 3 })
    ]
    github = [ Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/x", title: "Feed",
                                ref: "#14", timestamp: Time.new(2026, 7, 4, 9)) ]

    report = build(local: local, github: github, repos: %w[busy app])

    assert_equal %i[branch_wip dirty_tree pr_open], report.doing.map(&:kind)
    assert_empty report.quiet
  end

  def test_github_nil_adds_skip_note
    report = build(local: [], github: nil, repos: [])

    assert_includes report.notes, "GitHub: skipped (gh not available)"
  end

  def test_github_empty_produces_no_note
    report = build(local: [], github: [], repos: [])

    assert_empty report.notes
  end

  def test_github_truncation_adds_incomplete_note
    github = [ Spill::Event.new(source: :github, kind: :github_truncated, repo: nil,
                                extra: { oldest: Time.new(2026, 7, 1, 8) }) ]

    report = build(local: [], github: github, repos: [])

    assert_includes report.notes, "GitHub: may be incomplete before Jul 1"
  end

  def test_github_search_cap_adds_capped_note_without_dated_note
    github = [ Spill::Event.new(source: :github, kind: :github_search_capped, repo: nil) ]

    report = build(local: [], github: github, repos: [])

    assert_includes report.notes, "GitHub: search results may be incomplete (capped at 100)"
    refute(report.notes.any? { |note| note.include?("may be incomplete before") })
  end

  def test_both_truncation_kinds_produce_both_notes
    github = [
      Spill::Event.new(source: :github, kind: :github_search_capped, repo: nil),
      Spill::Event.new(source: :github, kind: :github_truncated, repo: nil,
                       extra: { oldest: Time.new(2026, 7, 1, 8) })
    ]

    report = build(local: [], github: github, repos: [])

    assert_includes report.notes, "GitHub: may be incomplete before Jul 1"
    assert_includes report.notes, "GitHub: search results may be incomplete (capped at 100)"
  end

  def test_github_done_is_chronological
    t = Time.new(2026, 7, 3, 12)
    github = [
      Spill::Event.new(source: :github, kind: :review, repo: "a/b", title: "Later", ref: "#2", timestamp: t + 60),
      Spill::Event.new(source: :github, kind: :pr_merged, repo: "a/b", title: "Earlier", ref: "#1", timestamp: t)
    ]

    report = build(github: github)

    assert_equal [ "Earlier", "Later" ], report.github_done.map(&:title)
  end

  def test_commented_events_are_in_github_done
    t = Time.new(2026, 7, 3, 12)
    github = [ Spill::Event.new(source: :github, kind: :commented, repo: "a/b", title: "Bug", ref: "#5", timestamp: t) ]

    report = build(github: github)

    assert_equal [ :commented ], report.github_done.map(&:kind)
  end

  def test_starred_events_populate_explored_not_done_or_doing
    t = Time.new(2026, 7, 3, 12)
    github = [
      Spill::Event.new(source: :github, kind: :starred, repo: "nilbuild/git-standup", timestamp: t),
      Spill::Event.new(source: :github, kind: :starred, repo: "mbailey/voicemode", timestamp: t + 60)
    ]

    report = build(github: github)

    assert_empty report.github_done
    assert_empty report.doing
    assert_equal [ "mbailey/voicemode", "nilbuild/git-standup" ], report.explored
  end

  def test_explored_dedupes_repo_keeping_latest_timestamp
    t = Time.new(2026, 7, 3, 12)
    github = [
      Spill::Event.new(source: :github, kind: :starred, repo: "a/b", timestamp: t),
      Spill::Event.new(source: :github, kind: :starred, repo: "a/b", timestamp: t + 60)
    ]

    report = build(github: github)

    assert_equal [ "a/b" ], report.explored
  end

  def test_explored_defaults_empty
    report = build(github: [])

    assert_empty report.explored
  end

  private

  def commit(repo, title, branch, time)
    Spill::Event.new(source: :local_git, kind: :commit, repo: repo, title: title,
                     ref: branch, timestamp: time, extra: { sha: "0" * 40 })
  end

  def build(local: [], github: [], repos: [])
    Spill::Report.build(local: local, github: github, repos: repos, window: WINDOW)
  end
end
