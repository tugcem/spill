require "optparse"

module Spill
  class CLI
    def self.run(argv, stdout: $stdout)
      options = { github: true }
      early_exit = false
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: spill [ROOT] [options]"
        opts.on("--since EXPR", 'Window start: "yesterday", "3 days ago", "2026-07-01"') { |v| options[:since] = v }
        opts.on("--author EMAIL", "Override the commit author for all repos") { |v| options[:author] = v }
        opts.on("--no-github", "Skip the GitHub layer") { options[:github] = false }
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

      report = build_report(args, options)
      color = stdout.respond_to?(:tty?) && stdout.tty? && ENV["NO_COLOR"].nil?
      stdout.puts Renderer.render(report, color: color)
      0
    rescue OptionParser::ParseError, ArgumentError => e
      stdout.puts "spill: #{e.message}"
      0
    end

    def self.build_report(args, options)
      window = options[:since] ? Window.parse(options[:since]) : Window.default
      repo_paths = RepoFinder.find(args.first || Dir.pwd)
      local = Collectors::LocalGit.new(repo_paths: repo_paths, author: options[:author])
                                  .collect(window: window)
      github = options[:github] ? Collectors::Github.new.collect(window: window) : []
      Report.build(local: local, github: github,
                   repos: repo_paths.map { |path| File.basename(path) }, window: window)
    end
  end
end
