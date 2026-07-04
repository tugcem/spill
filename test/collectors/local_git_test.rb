require "test_helper"
require "tmpdir"
require "fileutils"

class LocalGitCommitsTest < Minitest::Test
  WINDOW = Spill::Window.new(since: Time.now - 86_400, label: "test")

  def test_emits_commit_events_within_window_for_the_repo_author
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Old work", time: Time.now - (3 * 86_400))
      RepoFactory.commit(repo, "Fresh work", time: Time.now - 3_600)
      RepoFactory.commit(repo, "Someone else", time: Time.now - 3_600, email: "other@example.com")

      events = collect(repo)

      assert_equal [ "Fresh work" ], events.map(&:title)
      event = events.first
      assert_equal :commit, event.kind
      assert_equal "proj", event.repo
      assert_equal "main", event.ref
      assert_in_delta Time.now - 3_600, event.timestamp, 60
      assert_match(/\A\h{40}\z/, event.extra[:sha])
    end
  end

  def test_attributes_commits_to_head_branch_first_without_duplicates
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "On main", time: Time.now - 7_200)
      RepoFactory.git(repo, "checkout", "-q", "-b", "feature")
      RepoFactory.commit(repo, "On feature", time: Time.now - 3_600)
      RepoFactory.git(repo, "checkout", "-q", "main")

      events = collect(repo)

      assert_equal({ "On main" => "main", "On feature" => "feature" },
                   events.to_h { |e| [ e.title, e.ref ] })
    end
  end

  def test_excludes_merge_commits
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Base", time: Time.now - 7_200)
      RepoFactory.git(repo, "checkout", "-q", "-b", "feature")
      RepoFactory.commit(repo, "Feature work", time: Time.now - 3_600)
      RepoFactory.git(repo, "checkout", "-q", "main")
      RepoFactory.commit(repo, "Mainline work", time: Time.now - 3_500)
      RepoFactory.git(repo, "merge", "--no-ff", "-q", "-m", "Merge feature", "feature")

      titles = collect(repo).map(&:title)

      assert_includes titles, "Feature work"
      refute_includes titles, "Merge feature"
    end
  end

  def test_author_override_wins_over_repo_config
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Mine", time: Time.now - 3_600, email: "me@work.com")

      events = Spill::Collectors::LocalGit.new(repo_paths: [ repo ], author: "me@work.com")
                                          .collect(window: WINDOW)

      assert_equal [ "Mine" ], events.map(&:title)
    end
  end

  def test_nonexistent_repo_path_degrades_silently
    events = Spill::Collectors::LocalGit.new(repo_paths: [ "/nope/definitely-not-here" ])
                                        .collect(window: WINDOW)

    assert_empty events
  end

  private

  def collect(repo)
    Spill::Collectors::LocalGit.new(repo_paths: [ repo ]).collect(window: WINDOW)
  end
end

class LocalGitStateTest < Minitest::Test
  WINDOW = Spill::Window.new(since: Time.now - 86_400, label: "test")

  def test_dirty_tree_emits_file_count
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Base", time: Time.now - 3_600)
      File.write(File.join(repo, "wip-a.txt"), "x")
      File.write(File.join(repo, "wip-b.txt"), "y")

      dirty = collect(repo).find { |e| e.kind == :dirty_tree }

      assert_equal "proj", dirty.repo
      assert_equal 2, dirty.extra[:files]
    end
  end

  def test_clean_tree_emits_no_dirty_event
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Base", time: Time.now - 3_600)

      assert_nil collect(repo).find { |e| e.kind == :dirty_tree }
    end
  end

  def test_branch_ahead_of_upstream_is_wip
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Pushed", time: Time.now - 7_200)
      RepoFactory.add_bare_remote(repo, dir)
      RepoFactory.commit(repo, "Not pushed", time: Time.now - 3_600)

      wip = collect(repo).find { |e| e.kind == :branch_wip }

      assert_equal "main", wip.ref
      assert_equal 1, wip.extra[:ahead]
    end
  end

  def test_branch_without_upstream_in_repo_with_remote_is_wip
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Pushed", time: Time.now - 7_200)
      RepoFactory.add_bare_remote(repo, dir)
      RepoFactory.git(repo, "checkout", "-q", "-b", "feature")
      RepoFactory.commit(repo, "Local only", time: Time.now - 3_600)

      wip = collect(repo).find { |e| e.kind == :branch_wip }

      assert_equal "feature", wip.ref
      assert_equal 1, wip.extra[:unpushed]
      assert wip.extra[:no_upstream]
    end
  end

  def test_repo_with_no_remote_never_reports_unpushed
    Dir.mktmpdir do |dir|
      repo = RepoFactory.init_repo(File.join(dir, "proj"))
      RepoFactory.commit(repo, "Local forever", time: Time.now - 3_600)

      assert_empty collect(repo).select { |e| e.kind == :branch_wip }
    end
  end

  private

  def collect(repo)
    Spill::Collectors::LocalGit.new(repo_paths: [ repo ]).collect(window: WINDOW)
  end
end
