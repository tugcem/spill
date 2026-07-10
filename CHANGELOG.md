## [Unreleased]

## [0.5.1] - 2026-07-11

- The fact-block cap now keeps the newest facts: on a repo busy enough to
  overflow the block (roughly 40+ commits in the window), it used to keep the
  oldest commits and silently drop the newest ones and every GitHub fact
  (merged PRs included) from the AI summary.
- Repos using git's SHA-256 object format collect commits again — the commit
  parser rejected 64-character hashes, so those repos showed up as quiet.
- A commit log record with an unparseable date is now skipped on its own;
  previously it could error out the whole report.

## [0.5.0] - 2026-07-11

- Each key point may now run to three sentences (120-token cap) — enough for
  what got done and what's in flight, never a paragraph of filler.
- Commit message bodies now feed the summary: each commit contributes its
  body's first sentence (when it's short) alongside the subject, so a
  cryptic "fix" subject still produces a meaningful update. Dense multi-line
  bodies are left out — they measurably degrade the small model — trailers
  (Co-Authored-By: and friends) are stripped, and the report display itself
  is unchanged (subjects only).
- Fact blocks sent to the model are capped at 3000 characters, ending with
  an explicit "(and N more items not listed)" when a busy repo overflows.

## [0.4.0] - 2026-07-11

- The AI summary is now key points, one per repo — `• repo — sentence` —
  instead of a single paragraph that blended every project together. Each
  repo is summarized by its own on-device model call from an explicit list
  of its facts, so one repo's work can never bleed into another's line, no
  repo can be dropped or invented, and "opened" can't turn into "merged".
- Repos whose only activity is uncommitted changes or an unpushed branch
  are no longer sent to the model at all (there is nothing to summarize —
  and small models invent work when handed a bare file count).
- Model calls are capped (70 tokens, low temperature) to keep each key
  point to a sentence or two instead of a paragraph of filler.

## [0.3.0] - 2026-07-05

- An on-device AI summary (via Apple Intelligence / Foundation Models) now appears
  between the header and the report on macOS, when the model is available and
  stdout is a terminal: 2-4 first-person sentences on what was done and what's in
  flight. Fully local, zero config, no network calls, no API keys. Opt out with
  `--no-ai`. Absent everywhere else (Linux, piped output, model unavailable, no
  Swift toolchain) — the report renders exactly as before, no error, no note.

## [0.2.0] - 2026-07-05

- The report is now grouped per repo: commits and GitHub activity (merged/opened
  PRs, reviews, comments, issues closed) for a repo appear together under one
  subtitle, instead of local commits and a separate flat "GitHub" block.
- A PR opened and merged within the same window collapses into a single
  "opened and merged PR #N" line instead of two.
- Colored output: `DONE` renders bold green, `DOING` bold yellow, repo
  subtitles bold cyan, and branch/count lines, age suffixes, the quiet-repo
  line, the `Explored:` line, and notes render dim — same as before when
  color is off (non-TTY output or `NO_COLOR` set).
- A teapot spinner (🫖 spilling the tea...) animates on stderr while spill
  collects local git and GitHub data, when both stdout and stderr are a TTY.

## [0.1.3] - 2026-07-05

- Open PRs in DOING are now window-relative: shown only if created within the window
  or up to 14 days before it. Stalled months-old PRs no longer haunt the report.

## [0.1.2] - 2026-07-05

- Open PRs in DOING now show their age (`PR #804 open (org/repo) — Title · 7 months`),
  so a long-stale PR is visible at a glance instead of looking the same as one opened
  yesterday.
- Search results capped note: the three GitHub search calls (open/merged/opened PRs)
  now request up to 100 results (was 50); if any search hits that cap, the report notes
  `GitHub: search results may be incomplete (capped at 100)` — undated, since search
  results are relevance-sorted and a capped page has no chronological boundary. The
  dated events-feed note is unchanged and can appear alongside it.
- Test hardening: added regression coverage for cross-type comment dedupe (an
  `IssueCommentEvent` and a `PullRequestReviewCommentEvent` on the same thread still
  collapse to one `:commented` event).

## [0.1.1] - 2026-07-04

- Merged PRs now sourced via the search API instead of the events feed, fixing
  attribution (merges no longer get lost or misattributed to the merger).
- Opened PRs are sourced via the search API too, restoring titles that the thin
  events-feed payload didn't carry.
- New coverage: `:commented` events (issue and PR review comments, deduped per
  thread) and an `Explored:` line for repos you starred.
- GitHub work events are scoped to the repos under the scanned root (matched by
  origin remote); starred repos stay global.

## [0.1.0] - 2026-07-04

- Initial release: Done/Doing standup report from local git and GitHub (`gh`).
