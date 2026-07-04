require_relative "lib/spill/version"

Gem::Specification.new do |spec|
  spec.name = "spill"
  spec.version = Spill::VERSION
  spec.authors = [ "Tugcem Yalcin" ]
  spec.email = [ "tugcemyalcin@gmail.com" ]

  spec.summary = "Your standup, spilled: a Done/Doing report from local git and GitHub."
  spec.description = "spill scans a folder of git repos and prints a standup report — " \
                     "commits, PRs merged, reviews given, and work still in flight — " \
                     "synthesized from local git and (optionally) the GitHub CLI."
  spec.homepage = "https://github.com/tugcem/spill"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = [ "spill" ]
  spec.require_paths = [ "lib" ]
end
