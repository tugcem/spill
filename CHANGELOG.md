## [Unreleased]

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
