# HANDOFF — 2026-08-22 (PDT)

**Two-day infrastructure + family-project arc** (2026-08-20 → 08-22, sessions
back-to-back). Three threads: (1) Linear replaced GitHub Projects as the issue
tracker and the herdr fleet grew from five agents to eleven — including the first
Forge-resident hybrid (orrery) and Borealis's full de-Forge migration; (2) phone
access moved from Conduit to Moshi with the Conduit VPS pieces torn down; (3) a new
family project — automated KPI reporting for Brittanie (CRO @ ShipSigma) — was
designed, packaged, and handed off to *her* Claude account, where David reports
progress plus some blockers being worked through. **End state: dotfiles master
clean at `e0501b7`, no open PRs anywhere, board in Linear, KPI project live-in-
progress on Brittanie's MacBook.**

## What We Built

- **Linear migration (#155, #156).** Workspace `Villavicencio` (team `VIL`),
  project `Dotfiles`; old GH board (zero open, 44 closed) is read-only history.
  `/ticket` now drives `mcp__linear__save_issue`; merge cleanup marks issues Done.
  Linear MCP is global in `~/.claude.json` — **personal Mac only** (work Mac uses
  other tools; tickets from there via Linear web UI).
- **Borealis de-Forged (#157).** `~/.forge-projects/borealis` → `~/Projects/borealis`,
  new-slug memory symlink, workspace `borealis ❆`, jump `prefix+shift+b`. The
  Borealis agent then deleted its Forge scaffold (its commit `13e9cec`).
- **Fleet expansion (#158).** `argus ◉` (~/Projects/agents), `skills ⚒`,
  `obscura ✇` (~/Projects/browse-gateway), `eidos ❖` (~/Projects/eidos — got the
  full vault bootstrap). Jump keys shift+a/s/o/i; CLAUDE.md roster is now a table.
- **Forge-resident hybrid SOP + orrery (#159, #160).** `tranquil-dune` IS Orrery
  (live dashboard at orrery.ui8.dev) — herdr-ized in place as `orrery ☉`
  (jump `prefix+y`), `~/Projects/orrery` symlink is ergonomics-only. SOP in the
  Herdr section: physical-path pane cwd, shared slug across both harnesses,
  one-writer-at-a-time; **hybrid repos get a private remote and the PR is the
  seam** (orrery git-initialized → private `villavicencio/orrery`).
- **Moshi replaces Conduit (#161).** Phone → fleet is Moshi SSH/mosh to
  `zs-macbook-pro.tail31dc0a.ts.net` (key `moshi` in authorized_keys, `herdr`
  in-session). Conduit teardown on openclaw-prod: `conduit_push` plugin disabled +
  removed, pairing deleted, `tailscale serve` reset; gateway restarted healthy.
  Reversal: `/home/node/.hermes/backups/conduit-teardown-20260821-144904.tgz`.
- **ShipSigma KPI project** (private repo `villavicencio/shipsigma-kpi`, Linear
  project "ShipSigma KPI", VIL-17→21): full design package for Brittanie's
  automated CRO reporting — KPI definitions template, report formats, Project
  instructions, daily/weekly task prompts, sit-down walkthrough, truth-test
  checklist, sample brief + boss report, dashboard mockup artifact (Week/Goals/
  QoQ/YoY view switcher): https://claude.ai/code/artifact/64f049b6-9324-4bdf-b502-2fe62a58d3c6
  — plus the self-contained `HANDOFF-brittanie-setup.md` David pasted into her
  Claude.

## Decisions Made

- **Architecture: everything in Brittanie's own Max account** — official HubSpot
  connector (her admin OAuth) + Microsoft 365 connector (goals Excel on SharePoint,
  read fresh every run) + Cowork scheduled tasks (cloud-run). Zero custom infra;
  nothing on any of our machines at runtime. Ruled out: running it on David's
  side (compliance-gray for company CRM data).
- **Chat side, not Code tab**, on her app: Project for setup/Q&A, Scheduled page
  for the two tasks. Artifact-per-run reached from the Scheduled page; a stable
  bookmark URL is only a bonus if cross-run artifact updates prove out.
- **QoQ/YoY are same-point pacing** (QTD vs same-days-elapsed), never full-vs-partial;
  YoY carries a data-vintage caveat. Goals absent from the workbook render "no
  goal set," never inferred.
- **Truth test is the acceptance gate**: number-for-number vs her latest manual
  report, then one parallel cycle before she retires the manual process.
- Dotfiles CodeRabbit flow settled into: push → tracked background watcher →
  review findings → merge on CLEAN. (Detached `&` background jobs do NOT survive
  the Bash call — use `run_in_background` watchers only.)

## What Didn't Work

- **`tranquil-dune` was almost condemned as a Forge demo** — it's Orrery. The
  Borealis cleanup mission's step-4 got a correction blob; deletion was gated on
  confirmation so nothing was lost. Lesson: no-git + codename ≠ scaffold.
- Compound multi-line Bash scripts intermittently lose PATH (jq/nc "not found")
  and zsh doesn't word-split like bash — flat one-liners with absolute paths are
  the reliable shape for herdr socket/API scripting.
- `layout.apply` with `workspace_id: null` targets the FOCUSED workspace (dropped
  a stray tab into w1) — create the workspace first, then apply to its tab.

## What's Next

1. **ShipSigma KPI sit-down is IN PROGRESS on Brittanie's MacBook** — David
   reports progress + blockers being figured out. When he returns with the
   report-back items (final KPI definitions, truth-test results, what the
   blockers were), fold them into `~/Projects/shipsigma-kpi`, update the mockup
   to her layout decisions, close VIL-17→19 as earned. **Ask about the blockers
   first** — likely candidates: M365 connector admin consent, scheduled-task
   Project attachment, or connector data gaps.
2. Parallel-run cycle (VIL-20) once automation is live.
3. Passive: herdr upstream watches (#2960/#2961/#2966); `dotfiles ~` pane still
   on the old `exec claude` shape (rebuild kills the session — do it at a natural
   break).

## Gotchas & Watch-outs

- **shipsigma-kpi repo rule: structure and names in git, never target values** —
  company data stays in her workbook; the repo is the design bench only.
  `HANDOFF-brittanie-setup.md` is *generated* from `package/` by concatenation —
  edit package files, regenerate, re-pbcopy (assembly recipe in PR #8/#9 commits).
- Orrery repo: PR flow now (remote exists — no more local ff-merges); never
  force-add `src/data/dashboard.json`; no pre-commit hook, scan before committing
  data-shaped files.
- Moshi: first connect may pop the macOS firewall prompt for mosh-server; Conduit
  app on the phone is dead and deletable. Do NOT reintroduce a phone gateway.
- Linear MCP tools are deferred — ToolSearch first; pass real newlines in
  markdown, never `\n` escapes.
- Fleet roster + jump keys live as a table in dotfiles CLAUDE.md (Herdr section);
  renames still don't survive pane recreation — reapply after degraded restores.
