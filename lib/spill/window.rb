require "time"

module Spill
  Window = Data.define(:since, :label) do
    def self.default(now: Time.now)
      new(since: midnight(now) - 86_400, label: "today + yesterday")
    end

    def self.parse(expr, now: Time.now)
      text = expr.strip
      since =
        case text
        when "today" then midnight(now)
        when "yesterday" then midnight(now) - 86_400
        when /\A(\d+)\s+hours?\s+ago\z/ then now - ($1.to_i * 3_600)
        when /\A(\d+)\s+days?\s+ago\z/ then now - ($1.to_i * 86_400)
        when /\A(\d+)\s+weeks?\s+ago\z/ then now - ($1.to_i * 7 * 86_400)
        else Time.parse(text)
        end
      new(since: since, label: text)
    end

    def self.midnight(time)
      Time.new(time.year, time.month, time.day)
    end
  end
end
