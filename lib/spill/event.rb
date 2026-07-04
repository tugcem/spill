module Spill
  Event = Data.define(:source, :kind, :repo, :title, :ref, :timestamp, :extra) do
    def initialize(source:, kind:, repo:, title: nil, ref: nil, timestamp: nil, extra: {})
      super
    end
  end
end
