# spill 🍵

Your standup, spilled. `spill` scans a folder of git repos and prints what you
**did** and what you're **doing** — synthesized from local git and (optionally)
your GitHub activity via the `gh` CLI. Not a commit dump: merged PRs, reviews
you gave, comments you left, branches in flight, uncommitted work — even the
repos you starred along the way.

    $ cd ~/code && spill

    spill · Fri Jul 4 · today + yesterday

    DONE
      icebreaker-bingo · main · 7 commits
        Scaffold Rails 8.1 app on Ruby 4.0.4
        Add QR code page
      GitHub
        merged PR #12 (acme/website) — Fix nav
        reviewed PR #87 (acme/dashboard) — Payout calc
        commented on #103 (acme/website) — Rate limiting rollout

    DOING
      icebreaker-bingo · feed-page: 3 unpushed commits
      website: uncommitted changes (4 files)
      PR #14 open (acme/website) — Live feed

    3 quiet repos skipped

    Explored: nilbuild/git-standup

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

## Roadmap

Deployment detection, a NEXT section from issue trackers, and an LLM narrator —
see [docs/specs](docs/specs/) for the layered design.

## License

MIT
