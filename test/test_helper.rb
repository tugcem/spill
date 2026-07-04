$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Isolate tests from the developer's real git config (signing, hooks, identity).
ENV["GIT_CONFIG_GLOBAL"] = File::NULL
ENV["GIT_CONFIG_SYSTEM"] = File::NULL

require "spill"
require "minitest/autorun"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
