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
        PR #14 open — Live feed · 7 months

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

## Roadmap

Deployment detection, a NEXT section from issue trackers, and an LLM narrator —
see [docs/specs](docs/specs/) for the layered design.

## License

MIT
