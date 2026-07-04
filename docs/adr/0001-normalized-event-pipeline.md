# Normalized Event pipeline as the core architecture

spill's roadmap is layered sources (local git → GitHub → deployments → issue trackers →
LLM synthesis), and we decided every source must emit into one normalized `Spill::Event`
record rather than writing report sections directly. Collectors are optional adapters
(`collect(window:, identity:) → [Event] or nil`; nil = layer silently absent), the report
builder is a pure function over events, and renderers — including the future LLM one —
only ever see the structured report. The alternative (each layer rendering its own
section) would have been simpler for v0.1 but makes every later layer a core change;
with the event model, layers L3–L5 are new adapters plus at most one new renderer,
with zero changes to the pipeline.
