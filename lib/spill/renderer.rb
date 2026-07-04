module Spill
  module Renderer
    module_function

    def render(report, color: false, now: Time.now)
      lines = [ "#{style("spill", :bold, color)} · #{now.strftime("%a %b %-d")} · #{report.window.label}" ]
      if empty?(report)
        lines << "" << "Nothing to spill. 🍵"
      else
        lines.concat(done_lines(report, color))
        lines.concat(doing_lines(report, color))
        lines.concat(quiet_lines(report, color))
      end
      report.notes.each { |note| lines << "" << style(note, :dim, color) }
      lines.join("\n") << "\n"
    end

    def empty?(report)
      report.done.empty? && report.github_done.empty? && report.doing.empty?
    end

    def done_lines(report, color)
      return [] if report.done.empty? && report.github_done.empty?

      lines = [ "", style("DONE", :bold, color) ]
      report.done.each do |entry|
        entry[:branches].each do |branch|
          count = branch[:commits].size
          lines << "  #{entry[:repo]} · #{branch[:name]} · #{pluralize(count, "commit")}"
          branch[:commits].each { |commit| lines << "    #{commit.title}" }
        end
      end
      if report.github_done.any?
        lines << "  GitHub"
        report.github_done.each { |event| lines << "    #{github_line(event)}" }
      end
      lines
    end

    def doing_lines(report, color)
      return [] if report.doing.empty?

      [ "", style("DOING", :bold, color) ] +
        report.doing.map { |event| "  #{doing_line(event)}" }
    end

    def quiet_lines(report, color)
      return [] if report.quiet.empty?

      count = report.quiet.size
      [ "", style("#{count} quiet #{count == 1 ? "repo" : "repos"} skipped", :dim, color) ]
    end

    def github_line(event)
      verb = { pr_merged: "merged PR", pr_opened: "opened PR",
               review: "reviewed PR", issue_closed: "closed issue" }.fetch(event.kind)
      "#{verb} #{event.ref} (#{event.repo}) — #{event.title}"
    end

    def doing_line(event)
      case event.kind
      when :dirty_tree
        "#{event.repo}: uncommitted changes (#{pluralize(event.extra[:files], "file")})"
      when :branch_wip
        if event.extra[:no_upstream]
          "#{event.repo} · #{event.ref}: not pushed yet (#{pluralize(event.extra[:unpushed], "commit")})"
        else
          "#{event.repo} · #{event.ref}: #{event.extra[:ahead]} unpushed #{event.extra[:ahead] == 1 ? "commit" : "commits"}"
        end
      when :pr_open
        "PR #{event.ref.delete_prefix("#").prepend("#")} open (#{event.repo}) — #{event.title}"
      end
    end

    def pluralize(count, noun)
      "#{count} #{count == 1 ? noun : "#{noun}s"}"
    end

    def style(text, kind, color)
      return text unless color

      code = kind == :bold ? 1 : 2
      "\e[#{code}m#{text}\e[0m"
    end
  end
end
