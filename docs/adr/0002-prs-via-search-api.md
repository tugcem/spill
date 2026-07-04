# PR facts sourced from the search API, not the events feed

The GitHub events feed (`/users/<login>/events`) is actor-scoped and its `pull_request`
payload is thin: a PR you merge is attributed to whoever performed the merge rather
than the PR's author, and opened-PR events carry no title. Rather than accept
misattributed merges and title-less opens, `Spill::Collectors::Github` sources both
`:pr_opened` and `:pr_merged` from `gh api search/issues` with an `author:` qualifier
(`created:>=` and `merged:>=` respectively), matching the existing `:pr_open` snapshot
call. The consequence: two extra `gh` calls per run, and — since the search is scoped
to `author:<login>` — merges you perform on someone else's PR intentionally don't
appear in Done; that's a deliberate trade for correct attribution on your own PRs.
