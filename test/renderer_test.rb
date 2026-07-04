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
        bingo · main · 2 commits
          Add card page
          Add QR page
        GitHub
          merged PR #12 (acme/site) — Fix nav

      DOING
        bingo · feed: 3 unpushed commits
        site: uncommitted changes (4 files)
        PR #14 open (acme/site) — Feed

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

    assert_includes output, "bingo · feed: not pushed yet (1 commit)"
    assert_includes output, "site: uncommitted changes (1 file)"
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
    report = Spill::Report.build(local: [ commit("bingo", "X", "main", t) ],
                                 github: nil, repos: [ "bingo" ], window: WINDOW)

    output = Spill::Renderer.render(report, color: true, now: NOW)

    assert_includes output, "\e[1mDONE\e[0m"
    assert_includes output, "\e[2mGitHub: skipped (gh not available)\e[0m"
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

    assert_includes output, "merged PR #12 (acme/site)\n"
    assert_includes output, "PR #14 open (acme/site)\n"
  end

  private

  def commit(repo, title, branch, time)
    Spill::Event.new(source: :local_git, kind: :commit, repo: repo, title: title,
                     ref: branch, timestamp: time, extra: { sha: "0" * 40 })
  end
end
