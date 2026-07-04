require_relative "spill/version"
require_relative "spill/event"
require_relative "spill/window"
require_relative "spill/repo_finder"
require_relative "spill/collectors/local_git"

module Spill
  class Error < StandardError; end
end
