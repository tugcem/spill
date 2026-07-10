# spill 🍵

Your standup, spilled. `spill` scans a folder of git repos and prints what you
**did** and what you're **doing** — synthesized from local git and (optionally)
your GitHub activity via the `gh` CLI. Not a commit dump: merged PRs, reviews
you gave, comments you left, branches in flight, uncommitted work — even the
repos you starred along the way.

    $ cd ~/code && spill

    spill · Fri Jul 4 · today + yesterday

    DONE
      icebreaker-bingo
        main · 2 commits
          Scaffold Rails 8.1 app on Ruby 4.0.4
          Add QR code page
      acme/website
        opened and merged PR #12 — Fix nav
      acme/dashboard
        reviewed PR #87 — Payout calc
        commented on #103 — Rate limiting rollout

    DOING
      icebreaker-bingo
        feed-page: 3 unpushed commits
      acme/website
        uncommitted changes (4 files)
        PR #14 open — Live feed · 5 days

    3 quiet repos skipped

    Explored: nilbuild/git-standup

Everything is grouped per repo — commits and GitHub activity for a repo sit
under one subtitle. In a terminal, `DONE`/`DOING` and repo subtitles are
colored (green/yellow/cyan) and secondary lines are dimmed — set `NO_COLOR`
or pipe the output to disable it. While spill is collecting local git and
GitHub data, a small teapot spinner animates on stderr.

## Install

    gem install spill

Requires Ruby ≥ 3.2 and `git`. The GitHub section lights up automatically if
the [gh CLI](https://cli.github.com) is installed and authenticated — no
tokens, no config. No `gh`? Local git still works; the section is skipped.

## Usage

    spill                      # scan the current directory (repos up to 2 levels down)
    spill ~/code               # scan somewhere else
    spill --since "3 days ago" # wider window ("yesterday", "2 weeks ago", "2026-07-01")
    spill --author me@work.com # override the git author
    spill --no-github          # local git only
    spill --no-ai              # skip the AI summary

## The AI summary

On macOS, when Apple Intelligence's on-device model is available and you're
running in a terminal, spill adds key points right below the header — one
short first-person sentence per repo:

    • acme/website — Unified zone resolution and closed enforcement gaps;
      my API endpoints PR is still open.
    • spill — Hardened the narrator compile path with an atomic rename,
      a timeout, and failure caching.

Each repo gets its own model call over an explicit list of its facts, so
projects are never blended together. It runs entirely on-device via Apple's
Foundation Models framework: no API keys, no network calls, nothing leaves
your machine. The first run compiles a tiny Swift helper (needs Xcode
Command Line Tools); after that it's cached and instant. Skip it with
`--no-ai`. Everywhere else — Linux, piped output, the model unavailable, no
Swift toolchain — spill is unaffected: the report renders exactly as before,
silently.

## Roadmap

Deployment detection and a NEXT section from issue trackers — see
[docs/specs](docs/specs/) for the layered design.

## License

MIT
