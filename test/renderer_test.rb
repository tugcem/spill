require "test_helper"

class RendererTest < Minitest::Test
  NOW = Time.new(2026, 7, 4, 15, 30)
  WINDOW = Spill::Window.new(since: Time.new(2026, 7, 3), label: "today + yesterday")

  def test_renders_full_report
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [
        commit("bingo", "Add card page", "main", t),
        commit("bingo", "Add QR page", "main", t + 60),
        Spill::Event.new(source: :local_git, kind: :branch_wip, repo: "bingo",
                         ref: "feed", extra: { ahead: 3 }),
        Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "site", extra: { files: 4 })
      ],
      github: [
        Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/site", title: "Fix nav",
                         ref: "#12", timestamp: t + 120),
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180)
      ],
      repos: %w[bingo site q1 q2], window: WINDOW
    )

    expected = <<~TEXT
      spill · Sat Jul 4 · today + yesterday

      DONE
        acme/site
          merged PR #12 — Fix nav
        bingo
          main · 2 commits
            Add card page
            Add QR page

      DOING
        acme/site
          PR #14 open — Feed
        bingo
          feed: 3 unpushed commits
        site
          uncommitted changes (4 files)

      2 quiet repos skipped
    TEXT

    assert_equal expected, Spill::Renderer.render(report, now: NOW)
  end

  def test_renders_no_upstream_wip_and_singulars
    report = Spill::Report.build(
      local: [
        Spill::Event.new(source: :local_git, kind: :branch_wip, repo: "bingo",
                         ref: "feed", extra: { unpushed: 1, no_upstream: true }),
        Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "site", extra: { files: 1 })
      ],
      github: [], repos: %w[bingo site quiet], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "feed: not pushed yet (1 commit)"
    assert_includes output, "uncommitted changes (1 file)"
    assert_includes output, "1 quiet repo skipped"
  end

  def test_renders_empty_report_with_note
    report = Spill::Report.build(local: [], github: nil, repos: [], window: WINDOW)

    expected = <<~TEXT
      spill · Sat Jul 4 · today + yesterday

      Nothing to spill. 🍵

      GitHub: skipped (gh not available)
    TEXT

    assert_equal expected, Spill::Renderer.render(report, now: NOW)
  end

  def test_color_mode_bolds_headers_and_dims_notes
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [
        commit("bingo", "X", "main", t),
        Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "bingo", extra: { files: 1 })
      ],
      github: nil, repos: [ "bingo" ], window: WINDOW
    )

    output = Spill::Renderer.render(report, color: true, now: NOW)

    assert_includes output, "\e[1;32mDONE\e[0m"
    assert_includes output, "\e[1;33mDOING\e[0m"
    assert_includes output, "\e[1;36mbingo\e[0m"
    assert_includes output, "\e[2mGitHub: skipped (gh not available)\e[0m"
  end

  def test_color_mode_dims_branch_count_line_and_age_suffix
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [ commit("bingo", "X", "main", t) ],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180, extra: { opened_at: NOW - 3_600 })
      ],
      repos: [ "bingo" ], window: WINDOW
    )

    output = Spill::Renderer.render(report, color: true, now: NOW)

    assert_includes output, "\e[2mmain · 1 commit\e[0m"
    assert_includes output, "PR #14 open — Feed\e[2m · today\e[0m"
  end

  def test_color_false_emits_no_escape_codes
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [
        commit("bingo", "X", "main", t),
        Spill::Event.new(source: :local_git, kind: :dirty_tree, repo: "bingo", extra: { files: 1 })
      ],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180, extra: { opened_at: NOW - 3_600 })
      ],
      repos: [ "bingo" ], window: WINDOW
    )

    output = Spill::Renderer.render(report, color: false, now: NOW)

    refute_includes output, "\e["
  end

  def test_empty_title_omits_dangling_em_dash
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_merged, repo: "acme/site", title: "",
                         ref: "#12", timestamp: t + 120),
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "",
                         ref: "#14", timestamp: t + 180)
      ],
      repos: %w[bingo], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "merged PR #12\n"
    assert_includes output, "PR #14 open\n"
  end

  def test_open_pr_age_annotation_shows_months_for_old_pr
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180, extra: { opened_at: NOW - (210 * 86_400) })
      ],
      repos: [], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "PR #14 open — Feed · 7 months\n"
  end

  def test_open_pr_without_opened_at_has_no_age_annotation
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180)
      ],
      repos: [], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "PR #14 open — Feed\n"
  end

  def test_open_pr_age_annotation_shows_today_for_fresh_pr
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: t + 180, extra: { opened_at: NOW - 3_600 })
      ],
      repos: [], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "PR #14 open — Feed · today\n"
  end

  def test_open_pr_age_annotation_uses_singular_at_exact_boundaries
    assert_equal "1 day", age_suffix(NOW - (1 * 86_400))
    assert_equal "1 week", age_suffix(NOW - (7 * 86_400))
    assert_equal "1 month", age_suffix(NOW - (30 * 86_400))
    assert_equal "1 year", age_suffix(NOW - (365 * 86_400))
  end

  def test_open_pr_age_annotation_stays_plural_above_boundaries
    assert_equal "2 days", age_suffix(NOW - (2 * 86_400))
    assert_equal "2 weeks", age_suffix(NOW - (14 * 86_400))
    assert_equal "2 months", age_suffix(NOW - (60 * 86_400))
    assert_equal "2 years", age_suffix(NOW - (730 * 86_400))
  end

  def test_renders_commented_and_explored
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :commented, repo: "acme/site", title: "Fix nav",
                         ref: "#12", timestamp: t),
        Spill::Event.new(source: :github, kind: :starred, repo: "nilbuild/git-standup", timestamp: t + 10),
        Spill::Event.new(source: :github, kind: :starred, repo: "mbailey/voicemode", timestamp: t + 20)
      ],
      repos: [], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "commented on #12 — Fix nav"
    assert_includes output, "\nExplored: mbailey/voicemode, nilbuild/git-standup\n"
  end

  def test_explored_line_appears_with_nothing_to_spill
    t = Time.new(2026, 7, 3, 10)
    report = Spill::Report.build(
      local: [],
      github: [ Spill::Event.new(source: :github, kind: :starred, repo: "acme/site", timestamp: t) ],
      repos: [], window: WINDOW
    )

    output = Spill::Renderer.render(report, now: NOW)

    assert_includes output, "Nothing to spill. 🍵"
    assert_includes output, "Explored: acme/site"
  end

  def test_no_explored_section_when_nothing_starred
    report = Spill::Report.build(local: [], github: [], repos: [], window: WINDOW)

    output = Spill::Renderer.render(report, now: NOW)

    refute_includes output, "Explored:"
  end

  def test_summary_nil_leaves_output_unchanged
    report = Spill::Report.build(local: [], github: nil, repos: [], window: WINDOW)

    with_summary = Spill::Renderer.render(report, now: NOW, summary: nil)
    without_summary_arg = Spill::Renderer.render(report, now: NOW)

    assert_equal without_summary_arg, with_summary
  end

  def test_empty_summary_leaves_output_unchanged
    report = Spill::Report.build(local: [], github: nil, repos: [], window: WINDOW)

    with_summary = Spill::Renderer.render(report, now: NOW, summary: [])
    without_summary_arg = Spill::Renderer.render(report, now: NOW)

    assert_equal without_summary_arg, with_summary
  end

  def test_summary_renders_one_bullet_per_repo_after_the_header
    report = Spill::Report.build(local: [], github: nil, repos: [], window: WINDOW)

    output = Spill::Renderer.render(report, now: NOW, summary: [
      [ "bingo", "Shipped the card page." ],
      [ "acme/site", "Fixed the nav; the feed PR is still open." ]
    ])

    expected = <<~TEXT
      spill · Sat Jul 4 · today + yesterday

        • bingo — Shipped the card page.
        • acme/site — Fixed the nav; the feed PR is still open.

      Nothing to spill. 🍵

      GitHub: skipped (gh not available)
    TEXT
    assert_equal expected, output
  end

  def test_summary_bullets_are_styled_when_color_enabled
    report = Spill::Report.build(local: [], github: nil, repos: [], window: WINDOW)

    output = Spill::Renderer.render(report, color: true, now: NOW,
                                    summary: [ [ "bingo", "Shipped the card page." ] ])

    assert_includes output, "\e[1;36mbingo\e[0m"
    assert_includes output, "\e[3m— Shipped the card page.\e[0m"
  end

  private

  def commit(repo, title, branch, time)
    Spill::Event.new(source: :local_git, kind: :commit, repo: repo, title: title,
                     ref: branch, timestamp: time, extra: { sha: "0" * 40 })
  end

  def age_suffix(opened_at)
    report = Spill::Report.build(
      local: [],
      github: [
        Spill::Event.new(source: :github, kind: :pr_open, repo: "acme/site", title: "Feed",
                         ref: "#14", timestamp: Time.new(2026, 7, 3, 10), extra: { opened_at: opened_at })
      ],
      repos: [], window: WINDOW
    )
    Spill::Renderer.render(report, now: NOW)[/PR #14 open — Feed · (.+)\n/, 1]
  end
end
