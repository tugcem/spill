require "test_helper"
require "json"

class GithubCollectorTest < Minitest::Test
  WINDOW = Spill::Window.new(since: Time.now - 86_400, label: "test")

  def test_returns_nil_when_gh_fails
    collector = Spill::Collectors::Github.new(runner: ->(_args) { [ "", false ] })

    assert_nil collector.collect(window: WINDOW)
  end

  def test_maps_events_and_filters_by_window
    fresh = (Time.now - 3_600).utc.iso8601
    stale = (Time.now - (3 * 86_400)).utc.iso8601
    events = [
      gh_event("PullRequestEvent", fresh, action: "closed",
               pull_request: { "number" => 12, "title" => "Add card page", "merged" => true }),
      gh_event("PullRequestEvent", fresh, action: "closed",
               pull_request: { "number" => 13, "title" => "Abandoned", "merged" => false }),
      gh_event("PullRequestEvent", fresh, action: "opened",
               pull_request: { "number" => 14, "title" => "Add feed" }),
      gh_event("PullRequestReviewEvent", fresh, action: "created",
               pull_request: { "number" => 87, "title" => "Fix dashboard" }),
      gh_event("IssuesEvent", fresh, action: "closed",
               issue: { "number" => 5, "title" => "QR too small" }),
      gh_event("PullRequestEvent", stale, action: "opened",
               pull_request: { "number" => 1, "title" => "Too old" })
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    kinds = collector.collect(window: WINDOW).group_by(&:kind)

    assert_equal [ "#12" ], kinds[:pr_merged].map(&:ref)
    assert_equal [ "#14" ], kinds[:pr_opened].map(&:ref)
    assert_equal [ "#87" ], kinds[:review].map(&:ref)
    assert_equal [ "#5" ], kinds[:issue_closed].map(&:ref)
    assert_nil kinds[:pr_open] # search stubbed empty
    assert_equal "acme/proj", kinds[:pr_merged].first.repo
    assert_equal "Add card page", kinds[:pr_merged].first.title
  end

  def test_open_prs_become_pr_open_snapshot_events
    search = { "items" => [ {
      "number" => 14, "title" => "Add feed", "updated_at" => Time.now.utc.iso8601,
      "repository_url" => "https://api.github.com/repos/acme/proj"
    } ] }
    collector = Spill::Collectors::Github.new(runner: runner_with(events: [], search: search))

    open_pr = collector.collect(window: WINDOW).find { |e| e.kind == :pr_open }

    assert_equal "#14", open_pr.ref
    assert_equal "acme/proj", open_pr.repo
  end

  def test_full_three_pages_of_recent_events_flags_truncation
    fresh = (Time.now - 3_600).utc.iso8601
    page = Array.new(100) do
      gh_event("PullRequestEvent", fresh, action: "opened",
               pull_request: { "number" => 2, "title" => "Busy" })
    end
    collector = Spill::Collectors::Github.new(runner: runner_with(events: page * 3))

    truncated = collector.collect(window: WINDOW).find { |e| e.kind == :github_truncated }

    refute_nil truncated
    assert_kind_of Time, truncated.extra[:oldest]
  end

  def test_failed_open_pr_search_makes_whole_layer_nil
    runner = lambda do |args|
      endpoint = args[1].to_s
      if endpoint == "user"
        [ JSON.generate({ "login" => "tugcem" }), true ]
      elsif endpoint.start_with?("search/issues")
        [ "", false ]
      else
        [ JSON.generate([]), true ]
      end
    end
    collector = Spill::Collectors::Github.new(runner: runner)

    assert_nil collector.collect(window: WINDOW)
  end

  private

  def gh_event(type, created_at, action:, **payload)
    { "type" => type, "created_at" => created_at, "repo" => { "name" => "acme/proj" },
      "payload" => { "action" => action }.merge(payload.transform_keys(&:to_s)) }
  end

  def runner_with(events:, search: { "items" => [] })
    lambda do |args|
      endpoint = args[1].to_s
      if endpoint == "user"
        [ JSON.generate({ "login" => "tugcem" }), true ]
      elsif endpoint.start_with?("search/issues")
        [ JSON.generate(search), true ]
      elsif endpoint.start_with?("users/tugcem/events")
        page = endpoint[/[?&]page=(\d+)/, 1].to_i
        slice = events.each_slice(100).to_a[page - 1] || []
        [ JSON.generate(slice), true ]
      else
        [ "", false ]
      end
    end
  end
end
