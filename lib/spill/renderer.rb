module Spill
  module Renderer
    module_function

    def render(report, color: false, now: Time.now, summary: nil)
      lines = [ "#{style("spill", :bold, color)} · #{now.strftime("%a %b %-d")} · #{report.window.label}" ]
      lines.concat(summary_lines(summary, color))
      if empty?(report)
        lines << "" << "Nothing to spill. 🍵"
      else
        lines.concat(done_lines(report, color))
        lines.concat(doing_lines(report, color, now))
        lines.concat(quiet_lines(report, color))
      end
      lines.concat(explored_lines(report, color))
      report.notes.each { |note| lines << "" << style(note, :dim, color) }
      lines.join("\n") << "\n"
    end

    def empty?(report)
      report.done.empty? && report.doing.empty?
    end

    # summary is [ [ repo, sentence ], ... ] — one key point per repo.
    def summary_lines(summary, color)
      return [] if summary.nil? || summary.empty?

      lines = [ "" ]
      summary.each do |repo, text|
        lines << "  #{style("•", :dim, color)} #{style(repo, :bold_cyan, color)} #{style("— #{text}", :italic, color)}"
      end
      lines
    end

    def done_lines(report, color)
      return [] if report.done.empty?

      lines = [ "", style("DONE", :bold_green, color) ]
      report.done.each do |entry|
        lines << "  #{style(entry[:repo], :bold_cyan, color)}"
        entry[:branches].each do |branch|
          count = branch[:commits].size
          lines << "    #{style("#{branch[:name]} · #{pluralize(count, "commit")}", :dim, color)}"
          branch[:commits].each { |commit| lines << "      #{commit.title}" }
        end
        entry[:github].each { |event| lines << "    #{github_line(event)}" }
      end
      lines
    end

    def doing_lines(report, color, now)
      return [] if report.doing.empty?

      lines = [ "", style("DOING", :bold_yellow, color) ]
      report.doing.each do |entry|
        lines << "  #{style(entry[:repo], :bold_cyan, color)}"
        entry[:items].each { |event| lines << "    #{doing_line(event, now, color)}" }
      end
      lines
    end

    def quiet_lines(report, color)
      return [] if report.quiet.empty?

      count = report.quiet.size
      [ "", style("#{count} quiet #{count == 1 ? "repo" : "repos"} skipped", :dim, color) ]
    end

    def github_line(event)
      verb = { pr_merged: "merged PR", pr_opened: "opened PR", pr_opened_and_merged: "opened and merged PR",
               review: "reviewed PR", issue_closed: "closed issue", commented: "commented on" }.fetch(event.kind)
      "#{verb} #{event.ref}#{title_suffix(event.title)}"
    end

    def explored_lines(report, color)
      return [] if report.explored.empty?

      [ "", style("Explored: #{report.explored.join(", ")}", :dim, color) ]
    end

    def title_suffix(title)
      title.to_s.empty? ? "" : " — #{title}"
    end

    def doing_line(event, now, color)
      case event.kind
      when :dirty_tree
        "uncommitted changes (#{pluralize(event.extra[:files], "file")})"
      when :branch_wip
        if event.extra[:no_upstream]
          "#{event.ref}: not pushed yet (#{pluralize(event.extra[:unpushed], "commit")})"
        else
          "#{event.ref}: #{event.extra[:ahead]} unpushed #{event.extra[:ahead] == 1 ? "commit" : "commits"}"
        end
      when :pr_open
        line = "PR #{event.ref.delete_prefix("#").prepend("#")} open#{title_suffix(event.title)}"
        if event.extra[:opened_at]
          "#{line}#{style(" · #{age(event.extra[:opened_at], now)}", :dim, color)}"
        else
          line
        end
      end
    end

    def age(opened_at, now)
      days = (now - opened_at) / 86_400
      if days >= 365
        pluralize((days / 365).floor, "year")
      elsif days >= 30
        pluralize((days / 30).floor, "month")
      elsif days >= 7
        pluralize((days / 7).floor, "week")
      elsif days >= 1
        pluralize(days.floor, "day")
      else
        "today"
      end
    end

    def pluralize(count, noun)
      "#{count} #{count == 1 ? noun : "#{noun}s"}"
    end

    STYLE_CODES = {
      bold: "1",
      dim: "2",
      bold_green: "1;32",
      bold_yellow: "1;33",
      bold_cyan: "1;36",
      italic: "3"
    }.freeze

    def style(text, kind, color)
      return text unless color

      "\e[#{STYLE_CODES.fetch(kind)}m#{text}\e[0m"
    end
  end
end
