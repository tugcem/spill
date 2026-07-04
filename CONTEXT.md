# spill

A CLI that produces your standup report by synthesizing layered activity sources
(local git, GitHub, deployments, issue trackers) into a Done / Doing / Next summary.

## Language

**Report**:
The standup output for one run: the sections Done, Doing, and (when layers allow) Shipped and Next.

**Window**:
The reporting period. Defaults to "today + yesterday" — since 00:00 local time yesterday.

**Done**:
Work performed during the window: commits (on any branch, merged or not), PRs merged, reviews given, issues closed. Windowed activity — says nothing about merge or deploy status.
_Avoid_: completed, landed, finished

**Doing**:
In-flight work as of the moment the report runs: branches with unpushed commits, dirty working trees, your open PRs. A snapshot of current state, not windowed activity.
_Avoid_: WIP section, in-progress

**Shipped**:
Deploys that happened during the window (production, staging, etc.). Own section, present only when the deployments layer is enabled. Deployment is never a sub-state of Done.
_Avoid_: deployed (as a Done qualifier)

**Next**:
Work queued for you: assigned issues, sprint items. Present only when an issue-tracker layer is enabled.

**Layer**:
An optional, independent source of activity (local git, GitHub, deployments, issue tracker). Layers compose in any subset — none depends on another; the L1–L5 numbering is build order, not a dependency chain. Missing tools or credentials make a layer silently absent, never an error.
_Avoid_: stack, level

**Collector**:
The adapter that implements a layer: `collect(window:, identity:) → [Event] or nil`.

**Event**:
The normalized record every collector emits (source, kind, repo, title, ref, timestamp). Commits, reviews, deploys, and assigned tickets are all Events with different kinds.

**Quiet repo**:
A discovered repo contributing nothing to Done and nothing to Doing. Collapsed into a single count line in the report.
