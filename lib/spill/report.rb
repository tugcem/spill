module Spill
  Report = Data.define(:window, :done, :github_done, :doing, :quiet, :explored, :notes) do
    GITHUB_DONE_KINDS = %i[ pr_opened pr_merged review issue_closed commented ].freeze
    LOCAL_STATE_KINDS = %i[ branch_wip dirty_tree ].freeze

    def self.build(local:, github:, repos:, window:)
      local ||= []
      github_events = github || []
      commits = local.select { |event| event.kind == :commit }
      state = local.select { |event| LOCAL_STATE_KINDS.include?(event.kind) }

      new(
        window: window,
        done: build_done(commits),
        github_done: github_events.select { |e| GITHUB_DONE_KINDS.include?(e.kind) }.sort_by(&:timestamp),
        doing: build_doing(state, github_events),
        quiet: repos - (commits.map(&:repo) + state.map(&:repo)).uniq,
        explored: build_explored(github_events),
        notes: build_notes(github, github_events)
      )
    end

    def self.build_done(commits)
      commits.group_by(&:repo).map do |repo, events|
        branches = events.group_by(&:ref).map do |branch, list|
          { name: branch, commits: list.sort_by(&:timestamp) }
        end
        { repo: repo, branches: branches, last: events.map(&:timestamp).max }
      end.sort_by { |entry| entry[:last] }.reverse
    end

    def self.build_doing(state, github_events)
      open_prs = github_events.select { |e| e.kind == :pr_open }
                              .sort_by(&:timestamp).reverse
      state.sort_by { |e| [ e.repo, e.kind.to_s ] } + open_prs
    end

    def self.build_explored(github_events)
      github_events.select { |e| e.kind == :starred }
                   .group_by(&:repo)
                   .map { |repo, events| [ repo, events.map(&:timestamp).max ] }
                   .sort_by { |_repo, time| time }
                   .reverse
                   .map(&:first)
    end

    def self.build_notes(github, github_events)
      notes = []
      notes << "GitHub: skipped (gh not available)" if github.nil?
      truncated = github_events.find { |e| e.kind == :github_truncated }
      notes << "GitHub: may be incomplete before #{truncated.extra[:oldest].strftime("%b %-d")}" if truncated
      if github_events.any? { |e| e.kind == :github_search_capped }
        notes << "GitHub: search results may be incomplete (capped at 100)"
      end
      notes
    end
  end
end
