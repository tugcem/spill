require "optparse"

module Spill
  class CLI
    def self.run(argv, stdout: $stdout)
      options = { github: true, ai: true }
      early_exit = false
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: spill [ROOT] [options]"
        opts.on("--since EXPR", 'Window start: "yesterday", "3 days ago", "2026-07-01"') { |v| options[:since] = v }
        opts.on("--author EMAIL", "Override the commit author for all repos") { |v| options[:author] = v }
        opts.on("--no-github", "Skip the GitHub layer") { options[:github] = false }
        opts.on("--no-ai", "Skip the AI summary") { options[:ai] = false }
        opts.on("--version", "Print version") do
          stdout.puts Spill::VERSION
          early_exit = true
        end
        opts.on("-h", "--help", "Show this help") do
          stdout.puts opts
          early_exit = true
        end
      end

      args = parser.parse(argv)
      return 0 if early_exit

      now = Time.now
      spinner_enabled = $stderr.tty? && stdout.respond_to?(:tty?) && stdout.tty?
      report, summary = Spinner.around(enabled: spinner_enabled) { build_report_and_summary(args, options, stdout, now) }
      color = stdout.respond_to?(:tty?) && stdout.tty? && ENV["NO_COLOR"].nil?
      stdout.puts Renderer.render(report, color: color, now: now, summary: summary)
      0
    rescue OptionParser::ParseError, ArgumentError => e
      stdout.puts "spill: #{e.message}"
      0
    end

    def self.build_report_and_summary(args, options, stdout, now)
      report = build_report(args, options)
      summary = ai_enabled?(options, stdout) ? ai_summary(report) : nil
      [ report, summary ]
    end

    # One key point per repo: Briefs decides what each repo's facts are,
    # the narrator turns each block into a sentence, and pairing happens
    # here by position — a repo whose block failed just drops out.
    def self.ai_summary(report)
      briefs = Briefs.build(report)
      return nil if briefs.empty?

      summaries = Narrator.narrate(briefs.map(&:last))
      return nil if summaries.nil?

      pairs = briefs.map(&:first).zip(summaries).reject { |_repo, text| text.nil? }
      pairs.empty? ? nil : pairs
    end

    def self.ai_enabled?(options, stdout)
      options[:ai] && Narrator.available? && stdout.respond_to?(:tty?) && stdout.tty?
    end

    def self.build_report(args, options)
      window = options[:since] ? Window.parse(options[:since]) : Window.default
      repo_paths = RepoFinder.find(args.first || Dir.pwd)
      local = Collectors::LocalGit.new(repo_paths: repo_paths, author: options[:author])
                                  .collect(window: window)
      repo_map = RepoRemotes.slug_map(repo_paths)
      github = options[:github] ? fetch_github(repo_map, window) : []
      Report.build(local: local, github: github,
                   repos: repo_paths.map { |path| File.basename(path) }, window: window, repo_map: repo_map)
    end

    def self.fetch_github(repo_map, window)
      scope = repo_map.keys.to_set
      Collectors::Github.new.collect(window: window, scope: scope)
    end
  end
end
