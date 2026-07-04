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

  private

  def collect(repo)
    Spill::Collectors::LocalGit.new(repo_paths: [ repo ]).collect(window: WINDOW)
  end
end
