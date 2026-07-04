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

    assert_nil kinds[:pr_merged] # closed events no longer produce pr_merged
    assert_nil kinds[:pr_opened] # opened events no longer produce pr_opened (search-based now)
    assert_equal [ "#87" ], kinds[:review].map(&:ref)
    assert_equal [ "#5" ], kinds[:issue_closed].map(&:ref)
    assert_nil kinds[:pr_open] # search stubbed empty
  end

  def test_merged_pr_search_becomes_pr_merged_event
    merged_search = { "items" => [ {
      "number" => 12, "title" => "Add card page",
      "pull_request" => { "merged_at" => Time.now.utc.iso8601 },
      "closed_at" => Time.now.utc.iso8601,
      "repository_url" => "https://api.github.com/repos/acme/proj"
    } ] }
    collector = Spill::Collectors::Github.new(runner: runner_with(events: [], merged_search: merged_search))

    merged = collector.collect(window: WINDOW).find { |e| e.kind == :pr_merged }

    refute_nil merged
    assert_equal "#12", merged.ref
    assert_equal "acme/proj", merged.repo
    assert_equal "Add card page", merged.title
    assert_kind_of Time, merged.timestamp
  end

  def test_merged_pr_older_than_window_is_filtered_out
    merged_search = { "items" => [ {
      "number" => 99, "title" => "Ancient",
      "pull_request" => { "merged_at" => (Time.now - (3 * 86_400)).utc.iso8601 },
      "closed_at" => nil,
      "repository_url" => "https://api.github.com/repos/acme/proj"
    } ] }
    collector = Spill::Collectors::Github.new(runner: runner_with(events: [], merged_search: merged_search))

    merged = collector.collect(window: WINDOW).find { |e| e.kind == :pr_merged }

    assert_nil merged
  end

  def test_failed_merged_pr_search_makes_whole_layer_nil
    runner = lambda do |args|
      endpoint = args[1].to_s
      if endpoint == "user"
        [ JSON.generate({ "login" => "tugcem" }), true ]
      elsif endpoint.include?("merged:")
        [ "", false ]
      elsif endpoint.start_with?("search/issues")
        [ JSON.generate({ "items" => [] }), true ]
      else
        [ JSON.generate([]), true ]
      end
    end
    collector = Spill::Collectors::Github.new(runner: runner)

    assert_nil collector.collect(window: WINDOW)
  end

  def test_opened_pr_search_becomes_pr_opened_event
    opened_search = { "items" => [ {
      "number" => 14, "title" => "Add feed", "created_at" => Time.now.utc.iso8601,
      "repository_url" => "https://api.github.com/repos/acme/proj"
    } ] }
    collector = Spill::Collectors::Github.new(runner: runner_with(events: [], opened_search: opened_search))

    opened = collector.collect(window: WINDOW).find { |e| e.kind == :pr_opened }

    refute_nil opened
    assert_equal "#14", opened.ref
    assert_equal "acme/proj", opened.repo
    assert_equal "Add feed", opened.title
    assert_kind_of Time, opened.timestamp
  end

  def test_opened_pr_older_than_window_is_filtered_out
    opened_search = { "items" => [ {
      "number" => 99, "title" => "Ancient", "created_at" => (Time.now - (3 * 86_400)).utc.iso8601,
      "repository_url" => "https://api.github.com/repos/acme/proj"
    } ] }
    collector = Spill::Collectors::Github.new(runner: runner_with(events: [], opened_search: opened_search))

    opened = collector.collect(window: WINDOW).find { |e| e.kind == :pr_opened }

    assert_nil opened
  end

  def test_failed_opened_pr_search_makes_whole_layer_nil
    runner = lambda do |args|
      endpoint = args[1].to_s
      if endpoint == "user"
        [ JSON.generate({ "login" => "tugcem" }), true ]
      elsif endpoint.include?("created:")
        [ "", false ]
      elsif endpoint.start_with?("search/issues")
        [ JSON.generate({ "items" => [] }), true ]
      else
        [ JSON.generate([]), true ]
      end
    end
    collector = Spill::Collectors::Github.new(runner: runner)

    assert_nil collector.collect(window: WINDOW)
  end

  def test_issue_comment_event_becomes_commented
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      { "type" => "IssueCommentEvent", "created_at" => fresh, "repo" => { "name" => "acme/proj" },
        "payload" => { "action" => "created", "issue" => { "number" => 5, "title" => "Bug" } } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    commented = collector.collect(window: WINDOW).find { |e| e.kind == :commented }

    refute_nil commented
    assert_equal "#5", commented.ref
    assert_equal "Bug", commented.title
  end

  def test_pull_request_review_comment_event_becomes_commented
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      { "type" => "PullRequestReviewCommentEvent", "created_at" => fresh, "repo" => { "name" => "acme/proj" },
        "payload" => { "action" => "created", "pull_request" => { "number" => 9, "title" => nil } } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    commented = collector.collect(window: WINDOW).find { |e| e.kind == :commented }

    refute_nil commented
    assert_equal "#9", commented.ref
    assert_nil commented.title
  end

  def test_commented_events_on_same_thread_are_deduped_to_latest
    older = (Time.now - 3_600).utc.iso8601
    newer = (Time.now - 60).utc.iso8601
    events = [
      { "type" => "IssueCommentEvent", "created_at" => older, "repo" => { "name" => "acme/proj" },
        "payload" => { "action" => "created", "issue" => { "number" => 5, "title" => "Bug" } } },
      { "type" => "IssueCommentEvent", "created_at" => newer, "repo" => { "name" => "acme/proj" },
        "payload" => { "action" => "created", "issue" => { "number" => 5, "title" => "Bug" } } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    commented = collector.collect(window: WINDOW).select { |e| e.kind == :commented }

    assert_equal 1, commented.size
    assert_equal Time.parse(newer).localtime, commented.first.timestamp
  end

  def test_watch_event_becomes_starred
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      { "type" => "WatchEvent", "created_at" => fresh, "repo" => { "name" => "acme/proj" },
        "payload" => { "action" => "started" } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    starred = collector.collect(window: WINDOW).find { |e| e.kind == :starred }

    refute_nil starred
    assert_equal "acme/proj", starred.repo
    assert_nil starred.ref
    assert_nil starred.title
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

  def test_scoped_collect_keeps_in_scope_work_event_and_drops_out_of_scope
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      gh_event("IssuesEvent", fresh, action: "closed",
               issue: { "number" => 5, "title" => "In scope" }),
      { "type" => "IssuesEvent", "created_at" => fresh, "repo" => { "name" => "other/proj" },
        "payload" => { "action" => "closed", "issue" => { "number" => 6, "title" => "Out of scope" } } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    result = collector.collect(window: WINDOW, scope: Set["acme/proj"])
    refs = result.select { |e| e.kind == :issue_closed }.map(&:ref)

    assert_equal [ "#5" ], refs
  end

  def test_scoped_collect_keeps_starred_event_regardless_of_scope
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      { "type" => "WatchEvent", "created_at" => fresh, "repo" => { "name" => "someone/else" },
        "payload" => { "action" => "started" } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    result = collector.collect(window: WINDOW, scope: Set["acme/proj"])

    assert(result.any? { |e| e.kind == :starred && e.repo == "someone/else" })
  end

  def test_scoped_collect_matches_canonical_case_repo_against_downcased_scope
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      { "type" => "IssuesEvent", "created_at" => fresh, "repo" => { "name" => "Acme/Proj" },
        "payload" => { "action" => "closed", "issue" => { "number" => 7, "title" => "Case mismatch" } } }
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    result = collector.collect(window: WINDOW, scope: Set["acme/proj"])
    kept = result.find { |e| e.kind == :issue_closed }

    refute_nil kept
    assert_equal "Acme/Proj", kept.repo # display string keeps the API's casing
  end

  def test_malformed_payloads_are_skipped_not_raised
    fresh = (Time.now - 3_600).utc.iso8601
    events = [
      gh_event("PullRequestEvent", fresh, action: "opened"),
      gh_event("PullRequestEvent", nil, action: "opened",
               pull_request: { "number" => 20, "title" => "No timestamp" })
    ]
    collector = Spill::Collectors::Github.new(runner: runner_with(events: events))

    result = collector.collect(window: WINDOW)

    assert_equal [], result
  end

  private

  def gh_event(type, created_at, action:, **payload)
    { "type" => type, "created_at" => created_at, "repo" => { "name" => "acme/proj" },
      "payload" => { "action" => action }.merge(payload.transform_keys(&:to_s)) }
  end

  def runner_with(events:, search: { "items" => [] }, merged_search: { "items" => [] }, opened_search: { "items" => [] })
    lambda do |args|
      endpoint = args[1].to_s
      if endpoint == "user"
        [ JSON.generate({ "login" => "tugcem" }), true ]
      elsif endpoint.include?("merged:")
        [ JSON.generate(merged_search), true ]
      elsif endpoint.include?("created:")
        [ JSON.generate(opened_search), true ]
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
