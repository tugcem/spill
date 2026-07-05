# L5 narrator ships as a renderer-side adapter over on-device Apple Intelligence

Per the layer model (ADR 0001), L5 synthesis is "just another renderer" sitting on top of
the same structured `Report` every other layer already produces — no pipeline changes,
just a plain-text render of the report handed to an LLM and the resulting prose spliced
back in above the sections. It's default-on, the same auto-light-up philosophy as the
GitHub layer (`gh` present and authed → it just works): if Apple's on-device model is
available and stdout is a terminal, the summary appears; `--no-ai` opts out. The backend
is Apple's Foundation Models framework, reached through a version-stamped compiled Swift
shim (`lib/spill/narrator.swift`, compiled once per spill version into `~/.cache/spill/`)
rather than an interpreted script, so the ~1s Swift startup cost is paid once, not per
run. Rejected: cloud LLM APIs — an API key and network calls violate spill's zero-config,
nothing-leaves-your-machine soul; Ollama — an extra install burden for v0.3, though it
remains a plausible non-macOS fallback later. Consequence: the AI summary is a macOS-only
feature and silently absent everywhere else, matching every other layer's silent-absence
rule (ADR 0001).
