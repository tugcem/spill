require "test_helper"

class BriefsTest < Minitest::Test
  WINDOW = Spill::Window.new(since: Time.new(2026, 7, 3), label: "today + yesterday")

  def test_one_block_per_repo_with_explicit_facts
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [
        commit("bingo", "Add card page", "main", t),
        commit("bingo", "Add QR page", "main", t + 60),
        Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "bingo", extra: { files: 2 })
      ],
      github: [
        Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/site", title: "Fix nav",
                         ref: "#12", timestamp: t + 120),
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180)
      ],
      repos: %w[bingo site], window: WINDOW
    )

    briefs = Spill::Briefs.build(report)
    repos = briefs.map(&:first)

    assert_includes repos, "bingo"
    assert_includes repos, "acme/site"

    bingo = briefs.to_h["bingo"]
    assert_includes bingo, "FINISHED"
    assert_includes bingo, "Commit: Add card page"
    assert_includes bingo, "Commit: Add QR page"
    assert_includes bingo, "IN PROGRESS"
    assert_includes bingo, "Uncommitted local changes in 2 file(s)"

    site = briefs.to_h["acme/site"]
    assert_includes site, "Merged PR #12: Fix nav"
    assert_includes site, "PR #14 still open, not merged yet: Feed"
    refute_includes site, "Commit:"
  end

  def test_repo_with_only_local_state_gets_no_block
    report = Spill::Report.build(
      local: [
        Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "scratch", extra: { files: 1 }),
        Spill::Event.new(source: :local_git, kind: :branch_wip, repo: "scratch",
                         ref: "wip", extra: { ahead: 3 })
      ],
      github: [], repos: %w[scratch], window: WINDOW
    )

    assert_empty Spill::Briefs.build(report)
  end

  def test_repo_with_only_an_open_pr_still_gets_a_block
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: Time.new(2026, 7, 3, 10))
      ],
      repos: [], window: WINDOW
    )

    briefs = Spill::Briefs.build(report)

    assert_equal [ "acme/site" ], briefs.map(&:first)
    assert_includes briefs.to_h["acme/site"], "PR #14 still open, not merged yet: Feed"
  end

  def test_done_repos_come_before_doing_only_repos
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [ commit("zzz-repo", "Ship it", "main", t) ],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "aaa/early", title: "Feed",
                         ref: "#1", timestamp: t)
      ],
      repos: %w[zzz-repo], window: WINDOW
    )

    assert_equal [ "zzz-repo", "aaa/early" ], Spill::Briefs.build(report).map(&:first)
  end

  def test_opened_but_still_open_pr_is_stated_once_as_awaiting_merge
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_opened, repo: "acme/dash", title: "Misfits",
                         ref: "#71", timestamp: t),
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/dash", title: "Misfits",
                         ref: "#71", timestamp: t, extra: { opened_at: t })
      ],
      repos: [], window: WINDOW
    )

    block = Spill::Briefs.build(report).to_h["acme/dash"]

    assert_includes block, "Opened PR #71, awaiting merge: Misfits"
    refute_includes block, "FINISHED\nOpened PR"
    refute_includes block, "still open, not merged yet"
  end

  def test_empty_report_yields_no_briefs
    report = Spill::Report.build(local: [], github: [], repos: [], window: WINDOW)

    assert_empty Spill::Briefs.build(report)
  end

  private

  def commit(repo, title, branch, time)
    Spill::Event.new(source: :local_git, kind: :commit, repo: repo,
                     title: title, ref: branch, timestamp: time)
  end
end
