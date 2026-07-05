# spill — design

*2026-07-04*

## One-liner

Run `spill` in a folder of git repos and get a standup report — **Done / Doing / Next** —
synthesized from layered sources (local git, GitHub, deployments, issue trackers, LLM),
not a raw commit dump.

## Why

The incumbent, [git-standup](https://github.com/kamranahmedse/git-standup) (~7k stars),
walks your repos and prints raw `git log` lines: one noisy block per repo (including
repos with no activity), redundant author names, no notion of what was *finished* vs
*in flight*, and nothing beyond commits — no PRs, reviews, deploys, or tickets.
A standup answers "what did I accomplish, what am I doing, what's next" — `spill`
produces that answer directly, and gets smarter with each layer you enable.

## The layer model

Each layer works on its own; each new layer enriches the report. Layers are adapters —
if a layer's tool or credential is missing, it silently drops out.

| Layer | Source | Needs | Adds to the report |
|-------|--------|-------|--------------------|
| L1 | Local git | `git` only | Done: commits by repo/branch · Doing: unpushed branches, dirty trees |
| L2 | GitHub | `gh` CLI (authed) | Done: PRs merged, reviews given, issues closed · Doing: open PRs |
| L3 | Deployments | `gh` (Actions/tags first; Fly/Heroku/Vercel adapters later) | Done: "shipped v2.3 to production" |
| L4 | Issue trackers | GitHub Issues first; Notion/Asana/ClickUp adapters later | **Next**: what's assigned to you, sprint state |
| L5 | LLM synthesis | macOS + on-device Apple Intelligence (`FoundationModels`) | A 2-4 sentence first-person standup summary above the report |

**v0.1 (this build) ships L1 + L2.** L3 and L4 are designed for, not built.
**v0.3.0 ships L5** — ahead of L3/L4 — via Apple's on-device Foundation Models
framework rather than a cloud LLM API, keeping spill's zero-config, zero-network
posture; see [ADR 0003](../adr/0003-on-device-narrator.md).

## Architecture

The decision that makes the layers cheap: every collector emits into one normalized
**event model**. A commit, a PR review, a deploy, and an assigned ticket are all just:

```ruby
Spill::Event = Data.define(:source, :kind, :repo, :title, :ref, :timestamp, :extra)
# source: :local_git | :github | :deploys | :tracker
# kind:   :commit | :branch_wip | :dirty_tree | :pr_opened | :pr_merged |
#         :review | :issue_closed | :deploy | :assigned_issue | ...
```

Pipeline:

```
collectors (L1..L4, each optional) → [Event] → Report.build → renderer
```

- **Collector interface**: `collect(window:, identity:) → [Event] or nil`.
  `nil` (missing tool, no auth, network error) means the layer is absent — never raises.
- **`Spill::Report.build(events:, window:)`** — pure function; buckets events into
  **Done** (commits on pushed branches, merged PRs, reviews, issues closed, deploys),
  **Doing** (unpushed branches, dirty trees, open PRs), **Next** (assigned/sprint items —
  empty until L4), and collapses quiet repos.
- **Renderers** take the same structured report: terminal (v0.1), markdown (later),
  **LLM prose (L5 is "just another renderer")**.
- Config file `~/.spill.yml` (v0.2+) declares enabled layers and credentials; v0.1
  needs no config at all.

Adding L3–L5 later = new collector adapters + one new renderer. Zero core changes.

## v0.1 in detail (L1 + L2)

### CLI

```
spill                      # scan current directory, window = today + yesterday
spill ~/code               # scan a different root
spill --since "3 days ago" # different window: "yesterday", "N days/hours/weeks ago", or an ISO date
                           # (one parser resolves the instant; git and GitHub use the same value)
spill --author x@y.com     # override author (default: git config user.email)
spill --no-github          # skip the GitHub layer
```

- Repo discovery: find `.git` directories at the root itself and up to two levels
  below (`root/.git`, `root/*/.git`, `root/*/*/.git`) — running `spill` inside a
  single repo just works.
- Default window "today + yesterday" means: since 00:00 local time yesterday.
- Identity: effective `git config user.email` resolved **per repo** (work and personal
  emails can differ by repo); `--author` overrides all repos. The GitHub layer always
  reports whoever `gh` is authenticated as — `--author` does not affect it.
- Exit 0 always (it is a report, not a check).

### Output

Plain terminal text with subtle ANSI color, zero output dependencies:

*(format as of v0.2.0 — commits and GitHub activity grouped per repo, an
"opened and merged PR" collapse, and open-PR age suffixes)*

```
spill · Fri Jul 4 · today + yesterday

DONE
  icebreaker-bingo
    main · 7 commits
      Scaffold Rails 8.1 app on Ruby 4.0.4
      Add Player model with session token
      Add prompts list and Card model
      Add BingoDetector for 4x4 line detection
      Add join flow with cookie-based player session
      Add card page, square marking, and bingo events
      Add QR code page
  recyclesmart-website
    opened and merged PR #12 — Fix nav
  resmart-dashboard
    reviewed PR #87 — Payout calc

DOING
  icebreaker-bingo
    feed-page: 3 unpushed commits
  recyclesmart-website
    uncommitted changes (4 files)
    PR #14 open — Live feed · 5 days

3 quiet repos skipped

Explored: nilbuild/git-standup
```

In a terminal, `DONE`/`DOING` render bold green/yellow, repo subtitles bold
cyan, and secondary lines (branch/count lines, age suffixes, the quiet-repo
line, `Explored:`, notes) render dim; `NO_COLOR` and non-TTY output disable
all of it. A teapot spinner animates on stderr while local git and GitHub
data are being collected (v0.2.0+).

Rules:
- Commits grouped per repo, per branch; every subject shown, chronologically — no
  collapsing or truncation (decided 2026-07-04). Long windows produce long reports;
  that is the user's choice of window.
- Merge commits are excluded (`--no-merges`) — the merge itself is reported by the
  GitHub layer as `merged PR #N`; including both would double-report.
- Repos are ordered by recency (most recent commit first); the quiet-repo count
  line comes last.
- GitHub **work events** (reviews, comments, issues closed, PRs opened/merged/open)
  are scoped to the repos actually discovered under the scanned root, matched by
  each local repo's **origin remote** (`org/name` slug) — not by folder basename.
  Starred repos are exempt: the `Explored:` line stays global, since exploration
  is inherently about other people's repos. (Decided 2026-07-04, after real-world
  use showed GitHub activity from unrelated repos bleeding into a scoped report.)
- The GitHub events fetch is capped at 3 pages / 300 events (API limit). If the
  window extends past the oldest fetched event, the report notes:
  `GitHub: may be incomplete before <date>`. The three search calls (open/merged/opened
  PRs) are likewise capped at 100 results each; hitting that cap triggers a separate,
  undated note — `GitHub: search results may be incomplete (capped at 100)` — because
  search results are relevance-sorted, so a capped page has no chronological boundary.
  Both notes may appear together.
- Open PRs in DOING carry an age annotation — `PR #1060 open (org/repo) — Title · 12 days`
  — computed from the PR's `created_at` against render time. (Decided 2026-07-04.)
- Open PRs in DOING are window-relative, not an unwindowed snapshot: a PR appears only
  if it was created within the window or up to 14 days before `window.since` (the
  `OPEN_PR_GRACE_SECONDS` grace period). A PR whose `created_at` predates that cutoff —
  or is missing entirely — is dropped from the report; the age annotation above still
  applies to whatever remains. Dirty trees and unpushed branches are unaffected — they
  stay a pure, unwindowed snapshot. (Decided 2026-07-05, after real-world use showed
  months-old stalled PRs cluttering the report; supersedes the pure-snapshot framing
  for open PRs specifically.)
- Repos with no activity collapse into one trailing "N quiet repos skipped" line.
- Every dirty working tree appears in DOING, no matter how old the changes are —
  no staleness heuristics. (Decided 2026-07-04: honesty over magic.)
- "Unpushed" only exists where a remote exists: a branch with no upstream in a repo
  *with* a remote is shown as "not pushed yet (N commits)"; a repo with *no remote at
  all* never reports unpushed work (its in-window commits still count as Done).
- If `gh` is missing or unauthenticated: one line — `GitHub: skipped (gh not available)`.
- Nothing anywhere? Print `Nothing to spill. 🍵`
- Renderer honors `NO_COLOR` and non-TTY output by dropping ANSI codes.

### L1 collector — `Spill::Collectors::LocalGit`

Walks the root for repos; per repo shells out to `git`:
- `git log --all --author=<email> --since=<window>` → commits in window, with branch attribution
- `git status --porcelain` → dirty working tree (changed-file count)
- `git for-each-ref` + upstream `ahead` counts → branches with unpushed commits

### L2 collector — `Spill::Collectors::Github`

Two data sources, combined; either failing makes the whole layer `nil` (all-or-nothing):

- **Events feed** — `gh api /users/<login>/events?per_page=100` (up to 3 pages),
  filtered to the window, mapped:
  - `PullRequestReviewEvent` → `:review`
  - `IssuesEvent` (closed) → `:issue_closed`
  - `IssueCommentEvent` / `PullRequestReviewCommentEvent` (created) → `:commented`
    (deduped per thread, keeping the latest comment)
  - `WatchEvent` (started) → `:starred`
  - The events feed is actor-scoped and its `pull_request` payload is thin (no
    title), so PR facts are *not* read from it — see ADR 0002.
- **Search API** — three separate `gh api search/issues` calls, each all-or-nothing:
  - `is:pr+author:<login>+created:>=<since>` → `:pr_opened` (titles included)
  - `is:pr+author:<login>+merged:>=<since>` → `:pr_merged` (titles included,
    correctly attributed to the PR author rather than whoever merged it)
  - `is:pr+is:open+author:<login>` → `:pr_open` (Doing; filtered to window + 14-day
    grace on `created_at` — see the Doing rules above)

### Entry point

`exe/spill` → `Spill::CLI.run(argv)` — stdlib `OptionParser`, wires collectors →
report → renderer, prints.

## Dependencies

- **Zero runtime gem dependencies.** Shells out to `git` (required) and `gh` (optional).
- `required_ruby_version >= 3.2` so the community can install it; developed on Ruby 4.0.4.
  (Note: `Data.define` needs 3.2+, which is exactly the floor.)
- Dev dependencies only: minitest, rubocop (omakase), rake.

## Testing

Minitest, strict TDD (red → green per unit):
- **LocalGit collector**: build throwaway repos in `Dir.mktmpdir` (real `git init`,
  commits with controlled dates/authors) and assert on emitted events.
- **Github collector**: stub the `gh` invocation, feed recorded JSON fixtures.
- **Report builder / Renderer**: pure functions — plain unit tests, including
  empty-report, github-absent, and quiet-repo cases.
- **CLI**: one integration test end-to-end against a tmpdir of fixture repos.

## Distribution

- Scaffold with `bundle gem spill` (MIT license; executable at `exe/spill`).
- GitHub repo `spill`, CI via GitHub Actions (test + rubocop).
- Publish with `gem push` (owner runs this) once v0.1.0 is green.
- Name confirmed free on RubyGems as of 2026-07-04.
- Demo trick: `gem exec spill` runs it without installing.

## Release ladder

- **v0.1 (this weekend):** L1 + L2, event model, terminal renderer
- **v0.2 (shipped):** colored output, teapot spinner (deployments/`~/.spill.yml` deferred)
- **v0.3 (shipped):** L5 on-device AI summary via Apple Intelligence (`--no-ai` to skip) —
  taken out of order because it needed zero new infrastructure beyond a renderer, unlike L3/L4
- **v0.4:** L3 deployments (GitHub Actions deploy workflows + tags/releases); `~/.spill.yml`
- **v0.5:** L4 GitHub Issues → "Next" section; tracker adapter interface, then more
  L4 adapters (Notion, Asana, ClickUp, Confluence)
- **Also v1.1-ish:** `--markdown` renderer; Homebrew tap (`brew install tugcemyalcin/spill/spill`);
  homebrew-core someday if it earns the stars
