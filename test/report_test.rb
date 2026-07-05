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
    assert_equal [], report.done.first[:github]
    assert_equal [ "quiet" ], report.quiet
  end

  def test_mapped_github_event_joins_the_commit_group
    t = Time.new(2026, 7, 3, 10)
    local = [ commit("bingo", "Add card page", "main", t) ]
    github = [ Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/bingo", title: "Fix nav",
                                ref: "#12", timestamp: t + 120) ]

    report = build(local: local, github: github, repos: %w[bingo], repo_map: { "acme/bingo" => "bingo" })

    assert_equal [ "bingo" ], report.done.map { |entry| entry[:repo] }
    group = report.done.first
    assert_equal 1, group[:branches].size
    assert_equal [ :pr_merged ], group[:github].map(&:kind)
    assert_equal t + 120, group[:last]
  end

  def test_unmapped_github_event_forms_its_own_group_with_empty_branches
    t = Time.new(2026, 7, 3, 10)
    github = [ Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/other", title: "Fix",
                                ref: "#1", timestamp: t) ]

    report = build(github: github, repos: [])

    assert_equal [ "acme/other" ], report.done.map { |entry| entry[:repo] }
    group = report.done.first
    assert_equal [], group[:branches]
    assert_equal [ :pr_merged ], group[:github].map(&:kind)
  end

  def test_groups_sort_most_recent_first_across_commits_and_github
    t = Time.new(2026, 7, 3, 10)
    local = [ commit("bingo", "Add card page", "main", t) ]
    github = [ Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/site", title: "Fix nav",
                                ref: "#12", timestamp: t + 120) ]

    report = build(local: local, github: github, repos: %w[bingo])

    assert_equal [ "acme/site", "bingo" ], report.done.map { |entry| entry[:repo] }
  end

  def test_opened_and_merged_pair_collapses_to_single_event
    t = Time.new(2026, 7, 3, 10)
    github = [
      Spill::Event.new(source: :github, kind: :pr_opened, repo: "acme/site", title: "Old title",
                       ref: "#12", timestamp: t),
      Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/site", title: "Fix nav",
                       ref: "#12", timestamp: t + 3_600)
    ]

    report = build(github: github, repos: [])

    events = report.done.first[:github]
    assert_equal [ :pr_opened_and_merged ], events.map(&:kind)
    assert_equal "Fix nav", events.first.title
    assert_equal t + 3_600, events.first.timestamp
  end

  def test_lone_pr_merged_without_matching_opened_stays_pr_merged
    t = Time.new(2026, 7, 3, 10)
    github = [
      Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/site", title: "Fix nav",
                       ref: "#12", timestamp: t)
    ]

    report = build(github: github, repos: [])

    assert_equal [ :pr_merged ], report.done.first[:github].map(&:kind)
  end

  def test_opened_and_merged_pair_in_different_repos_does_not_collapse
    t = Time.new(2026, 7, 3, 10)
    github = [
      Spill::Event.new(source: :github, kind: :pr_opened, repo: "acme/a", title: "A",
                       ref: "#1", timestamp: t),
      Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/b", title: "B",
                       ref: "#1", timestamp: t + 60)
    ]

    report = build(github: github, repos: [])

    kinds = report.done.flat_map { |entry| entry[:github].map(&:kind) }
    assert_equal %i[pr_opened pr_merged].sort, kinds.sort
  end

  def test_done_github_events_within_a_group_are_chronological
    t = Time.new(2026, 7, 3, 12)
    github = [
      Spill::Event.new(source: :github, kind: :review, repo: "a/b", title: "Later", ref: "#2", timestamp: t + 60),
      Spill::Event.new(source: :github, kind: :issue_closed, repo: "a/b", title: "Earlier", ref: "#1", timestamp: t)
    ]

    report = build(github: github, repos: [])

    assert_equal [ "Earlier", "Later" ], report.done.first[:github].map(&:title)
  end

  def test_commented_events_are_in_done
    t = Time.new(2026, 7, 3, 12)
    github = [ Spill::Event.new(source: :github, kind: :commented, repo: "a/b", title: "Bug", ref: "#5", timestamp: t) ]

    report = build(github: github, repos: [])

    assert_equal [ :commented ], report.done.first[:github].map(&:kind)
  end

  def test_doing_collects_state_then_open_prs
    local = [
      Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "busy", extra: { files: 2 }),
      Spill::Event.new(source: :local_git, kind: :branch_wip, repo: "app", ref: "wip", extra: { ahead: 3 })
    ]
    github = [ Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/x", title: "Feed",
                                ref: "#14", timestamp: Time.new(2026, 7, 4, 9)) ]

    report = build(local: local, github: github, repos: %w[busy app])

    assert_equal %w[acme/x app busy], report.doing.map { |entry| entry[:repo] }
    assert_equal %i[branch_wip], report.doing.find { |e| e[:repo] == "app" }[:items].map(&:kind)
    assert_equal %i[dirty_tree], report.doing.find { |e| e[:repo] == "busy" }[:items].map(&:kind)
    assert_equal %i[pr_open], report.doing.find { |e| e[:repo] == "acme/x" }[:items].map(&:kind)
    assert_empty report.quiet
  end

  def test_doing_orders_dirty_tree_then_branch_wip_then_pr_open_newest_first
    local = [
      Spill::Event.new(source: :local_git, kind: :branch_wip, repo: "bingo", ref: "b", extra: { ahead: 1 }),
      Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "bingo", extra: { files: 1 })
    ]
    github = [
      Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/bingo", title: "Old",
                       ref: "#1", timestamp: Time.new(2026, 7, 3, 9)),
      Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/bingo", title: "New",
                       ref: "#2", timestamp: Time.new(2026, 7, 4, 9))
    ]

    report = build(local: local, github: github, repos: %w[bingo], repo_map: { "acme/bingo" => "bingo" })

    group = report.doing.find { |e| e[:repo] == "bingo" }
    assert_equal [ :dirty_tree, :branch_wip, :pr_open, :pr_open ], group[:items].map(&:kind)
    assert_equal [ "New", "Old" ], group[:items].last(2).map(&:title)
  end

  def test_doing_pr_open_maps_via_repo_map
    github = [ Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/bingo", title: "Feed",
                                ref: "#14", timestamp: Time.new(2026, 7, 4, 9)) ]

    report = build(github: github, repos: %w[bingo], repo_map: { "acme/bingo" => "bingo" })

    assert_equal [ "bingo" ], report.doing.map { |entry| entry[:repo] }
  end

  def test_quiet_excludes_repos_with_mapped_github_activity_only
    github = [ Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/bingo", title: "Fix",
                                ref: "#1", timestamp: Time.new(2026, 7, 3, 10)) ]

    report = build(github: github, repos: %w[bingo quiet], repo_map: { "acme/bingo" => "bingo" })

    assert_equal [ "quiet" ], report.quiet
  end

  def test_quiet_excludes_repos_with_mapped_open_pr_only
    github = [ Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/bingo", title: "Feed",
                                ref: "#14", timestamp: Time.new(2026, 7, 4, 9)) ]

    report = build(github: github, repos: %w[bingo quiet], repo_map: { "acme/bingo" => "bingo" })

    assert_equal [ "quiet" ], report.quiet
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

  def test_starred_events_populate_explored_not_done_or_doing
    t = Time.new(2026, 7, 3, 12)
    github = [
      Spill::Event.new(source: :github, kind: :starred, repo: "nilbuild/git-standup", timestamp: t),
      Spill::Event.new(source: :github, kind: :starred, repo: "mbailey/voicemode", timestamp: t + 60)
    ]

    report = build(github: github)

    assert_empty report.done
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

  def build(local: [], github: [], repos: [], repo_map: {})
    Spill::Report.build(local: local, github: github, repos: repos, window: WINDOW, repo_map: repo_map)
  end
end
