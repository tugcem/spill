## [Unreleased]

## [0.1.2] - 2026-07-04

- Open PRs in DOING now show their age (`PR #804 open (org/repo) — Title · 7 months`),
  so a long-stale PR is visible at a glance instead of looking the same as one opened
  yesterday.
- Search results capped note: the three GitHub search calls (open/merged/opened PRs)
  now request up to 100 results (was 50); if a search hits that cap, the report notes
  `GitHub: may be incomplete before <date>`, same as the events-feed truncation note.
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
