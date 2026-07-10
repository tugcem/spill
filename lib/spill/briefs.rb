module Spill
  # Builds one fact block per repo for the narrator: explicit, unambiguous
  # statements derived from the report structure rather than rendered output,
  # so the small on-device model can't misread "opened" as "merged" or turn
  # a file count into invented work. Repos whose only activity is a dirty
  # tree or an unpushed branch carry nothing worth summarizing and get no
  # block at all — the model never sees them.
  module Briefs
    module_function

    FINISHED_VERBS = {
      pr_merged: "Merged PR",
      pr_opened: "Opened PR",
      pr_opened_and_merged: "Opened and merged PR",
      review: "Reviewed PR",
      issue_closed: "Closed issue",
      commented: "Commented on"
    }.freeze

    # Returns [ [ repo, block ], ... ] — done repos first (report order,
    # most recent first), then repos that only appear in doing.
    def build(report)
      open_refs = pr_refs(report.doing, :items) { |event| event.kind == :pr_open }
      opened_refs = pr_refs(report.done, :github) { |event| event.kind == :pr_opened }

      finished = {}
      report.done.each { |entry| finished[entry[:repo]] = finished_facts(entry, open_refs) }
      in_progress = {}
      report.doing.each { |entry| in_progress[entry[:repo]] = doing_facts(entry, opened_refs) }

      ordered = finished.keys + (in_progress.keys - finished.keys)
      ordered.filter_map do |repo|
        block = block_for(finished[repo] || [], in_progress[repo] || [])
        [ repo, block ] if summarizable?(repo, finished, report)
      end
    end

    def summarizable?(repo, finished, report)
      return true if finished[repo]&.any?

      entry = report.doing.find { |e| e[:repo] == repo }
      entry ? entry[:items].any? { |event| event.kind == :pr_open } : false
    end

    def block_for(finished_facts, doing_facts)
      lines = []
      lines << "FINISHED" << finished_facts if finished_facts.any?
      lines << "IN PROGRESS" << doing_facts if doing_facts.any?
      lines.flatten.join("\n")
    end

    # A PR that was opened in the window but is still open would appear
    # twice — "Opened PR #N" under FINISHED and "PR #N open" under IN
    # PROGRESS — and the model reads that pairing as a merge. State it once,
    # in IN PROGRESS, as "Opened PR #N, awaiting merge".
    def finished_facts(entry, open_refs)
      commits = entry[:branches].flat_map do |branch|
        branch[:commits].map { |commit| "Commit: #{commit.title}" }
      end
      github = entry[:github].filter_map do |event|
        next if event.kind == :pr_opened && open_refs[entry[:repo]]&.include?(normalize_ref(event.ref))

        "#{FINISHED_VERBS.fetch(event.kind)} #{normalize_ref(event.ref)}#{title_suffix(event.title)}"
      end
      commits + github
    end

    def doing_facts(entry, opened_refs)
      entry[:items].filter_map do |event|
        case event.kind
        when :pr_open
          ref = normalize_ref(event.ref)
          if opened_refs[entry[:repo]]&.include?(ref)
            "Opened PR #{ref}, awaiting merge#{title_suffix(event.title)}"
          else
            "PR #{ref} still open, not merged yet#{title_suffix(event.title)}"
          end
        when :dirty_tree
          "Uncommitted local changes in #{event.extra[:files]} file(s)"
        when :branch_wip
          count = event.extra[:no_upstream] ? event.extra[:unpushed] : event.extra[:ahead]
          "Branch #{event.ref}: #{count} commit(s) not pushed yet"
        end
      end
    end

    def pr_refs(groups, key, &matcher)
      groups.to_h do |entry|
        [ entry[:repo], entry[key].select(&matcher).map { |event| normalize_ref(event.ref) } ]
      end
    end

    def normalize_ref(ref)
      ref.to_s.delete_prefix("#").prepend("#")
    end

    def title_suffix(title)
      title.to_s.empty? ? "" : ": #{title}"
    end
  end
end
