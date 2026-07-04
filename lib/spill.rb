require_relative "spill/version"
require_relative "spill/event"
require_relative "spill/window"
require_relative "spill/repo_finder"
require_relative "spill/collectors/local_git"
require_relative "spill/collectors/github"
require_relative "spill/report"
require_relative "spill/renderer"

module Spill
  class Error < StandardError; end
end
