module Spill
  module Spinner
    FRAMES = [ "🫖  spilling the tea", "🫖  spilling the tea.", "🫖  spilling the tea..", "🍵  spilling the tea..." ].freeze
    INTERVAL = 0.15

    module_function

    def around(enabled:, out: $stderr)
      return yield unless enabled

      thread = spin(out)
      begin
        yield
      ensure
        thread.kill
        thread.join
        out.print "\r\e[K"
      end
    end

    def spin(out)
      Thread.new do
        i = 0
        loop do
          out.print "\r\e[K#{FRAMES[i % FRAMES.size]}"
          i += 1
          sleep INTERVAL
        end
      end
    end
  end
end
