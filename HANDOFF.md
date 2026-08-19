# HANDOFF — 2026-08-18 (PDT), evening

**Herdr improvements day, part two.** Same-day continuation of the morning's herdr adoption
(see PR #138's handoff via git history): David cleared context (`/clear herdr-improvements`)
and we worked the approved improvements list end-to-end. Eight PRs merged (#139–#146, the
last being this handoff), three upstream herdr issues filed, two solutions docs compounded,
one machine reboot mid-session (which doubled as the restart-resilience test — this very
session auto-resumed through it). **End state: single-branch repo** (`master` only, local
and remote; stale `feat/herdr` and all merged feature branches pruned), **empty board**
(#101 closed as accepted risk), no open PRs, clean tree.

## What We Built

- **PR #139 — statusline git-diff badge.** The `(+N/-M)` next to the branch now sums
  `git diff --numstat HEAD` (staged+unstaged, binary-safe, hidden on clean tree) instead of
  the session-cumulative `.cost.total_lines_*`. Fixture-verified against `git diff --stat`.
- **Axiom in herdr** (live config, recorded via #140): workspace `axiom ∴` runs the attach
  `ssh -t root@openclaw-prod 'sudo -u node tmux -L axiom attach -t AXIOM'` through
  `~/.local/bin/claude-code → /usr/bin/ssh` (claude-manifest alias); two idempotent
  `set-titles` options on the axiom tmux socket; agent renamed `axiom`. **The old memory was
  stale**: since the 2026-07-14 vault fold AXIOM runs as **node** on socket `-L axiom` —
  memory files corrected.
- **PR #140 — fleet + review-tool drift**: Brewfile gains `mosh` + `cask "coderabbit"`; the
  ssh shims became Dotbot-managed (`helpers/install_herdr_agents.sh`, darwin.yaml); CLAUDE.md/
  AGENTS.md herdr sections updated.
- **PR #141 + #143-rider — the HERDR_AGENT correction arc**: the "env pin is dead" finding was
  a `ps eww` measurement artifact (macOS hides other processes' env). Docs corrected twice as
  understanding improved (see Decisions).
- **PR #142 — hero-style sidebar**: agents panel rows `state · agent` with lavender agent
  tokens, `row_gap = 1`, accent `#cba6f7`, pane-border labels, `remove_worktree =
  "prefix+shift+e"`, and the **launchd-PATH fix** that made `prefix+a`/`prefix+d` jump keys
  work (absolute `/opt/homebrew/bin/herdr` in `[[keys.command]]`).
- **PR #143 — compound round**: two solutions docs —
  `docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md` (the
  session's three measurement artifacts + in-band-probe methodology) and
  `docs/solutions/integration-issues/launchd-service-bare-environment-silent-failures.md`
  (the bug-track companion), cross-linked; INDEX regenerated (47 active).
- **PR #144 — `agent_panel_sort = "priority"`** (attention queue) + topgrade lazy-lock drift.
- **PR #145 — RVM/pyenv lazy-loader `command` guards** (`ruby` recursed to FUNCNEST in
  harness snapshot shells that replay shims without `_load_*`; NVM already had the guard) +
  spaces-list `row_gap = 1` + the restore boot-race caveat in CLAUDE.md.
- **Upstream filings**: herdrdev/herdr#2960 (filed, then corrected + retitled: `type="shell"`
  key commands spawn with the launchd env, PATH failures silent), #2961 (agent-pin feature
  request → closed "already supported" via documented wrapper-foreground `HERDR_AGENT` hint;
  our ssh non-repro posted in-thread), #2966 (restore after reboot degrades command panes to
  shells and drops `command` from the layout).
- **Codex herdr integration** installed by David, audited clean (v7; merged beside Otty hooks
  in `~/.codex/hooks.json`; codex may ask once to trust the new hook).
- **Memory updates**: axiom lifecycle corrected (node + `-L axiom`); CodeRabbit rate-limit
  fallback ladder recorded (David-approved) in `coderabbit_gauntlet_evaluation.md`.

## Decisions Made

- **CodeRabbit rate-limit ladder (standing, in memory)**: CodeRabbit when available → wait
  out the window if not urgent (check reads "Review rate limited"; retrigger with
  `@coderabbitai review`) → `dv:gauntlet report` if a review is needed now → bare gauntlet
  only for big/risky diffs.
- **`prefix+d` for Axiom, not `prefix+shift+a`** — but the real story: NO custom binding chord
  was ever the problem; all `[[keys.command]]` failures were launchd-PATH. Keys hot-reload fine.
- **Hero styling adopted wholesale** (rows, accent, spacing, priority sort) after screenshot
  comparison; the reference image is herdr.dev's own hero mock, not a stock default.
- **Instrument-verification methodology** is now durable doctrine (see the new best-practices
  doc): calibrate the instrument against a known-true case; in-band probes over outside
  observers; a second reading through the same blind instrument is not corroboration; a probe
  answers only the question it poses.

## What Didn't Work

- **Three (nearly four) measurement artifacts in one day**, each a blind instrument: `ps eww`
  can't read other processes' env on macOS (faked "HERDR_AGENT absent"); herdr's log never
  records shell-spawn failures (faked "reload-config no-ops on keys" → mis-filed #2960, since
  corrected); and the "no env-pin feature" conclusion outran the printenv probe (the wrapper
  hint IS documented — just not firing for ssh foregrounds, repro posted to #2961). Full
  write-up in the new best-practices doc — read it before trusting any negative.
- **Restore after reboot dropped declarative pane commands** (atlas/axiom came back as bare
  shells; `command` gone from `layout.export`). Re-applied via `layout.apply`; filed #2966.
  Agent renames don't survive pane recreation either — reapply `herdr agent rename`.
- **CodeRabbit hit its 3-per-window rate limit twice**; the check still stamps green
  ("pass — Review rate limited"), so CLEAN ≠ last-commits-reviewed. Ladder in memory covers it.
- **`herdr api` CLI has no generic call surface** — raw NDJSON to `~/.config/herdr/herdr.sock`
  (scratchpad helper `herdr_call.py` pattern; schema via `herdr api schema --output`).

## What's Next

1. **Nothing is open.** Board is empty — issue #101 (install_omz staging-swap) was closed
   as accepted risk 2026-08-18 evening (David: "I hate that sometimes we over-engineer");
   the closing comment documents the rationale. Docker Desktop first launch: done same
   evening.
2. **One human-side item left**: Touch ID sudo_local on the **work** Mac (steps in
   CLAUDE.md "Touch ID for sudo"; escape-hatch second terminal).
3. **Passive upstream watches**: replies may arrive on herdrdev/herdr#2960 / #2961 (ssh
   non-repro question stands) / #2966. Re-test the `HERDR_AGENT` ssh case on the next herdr
   release.
4. Cosmetic/later: custom done/request sounds, per-agent `[ui.sound]`; herdr-on-VPS migration
   stays parked.

## Gotchas & Watch-outs (durable — the big ones landed in CLAUDE.md/docs this session)

- **launchd services run with bare PATH** — anything a `brew services` daemon executes needs
  absolute paths; failures are silent; server-side "not found" panels lie. See
  `docs/solutions/integration-issues/launchd-service-bare-environment-silent-failures.md`.
- **Verify negatives with in-band probes** — see
  `docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md`.
- **Herdr restore boot-race** (CLAUDE.md lifecycle bullet): failed pane commands degrade to
  shells AND drop from the layout; fix = re-run `layout.apply`; upstream #2966.
- **Herdr keys/UI hot-reload fine** (`reload-config`); the old "startup-only" claim is dead.
- **AXIOM attach**: `sudo -u node tmux -L axiom attach -t AXIOM` (node user, dedicated
  socket — the axiom-user form in older notes is defunct).
- **Computer use works from Claude Code now** — TCC grants applied after the reboot; iTerm
  resolves as app name "iTerm" (not "iTerm2"), granted at tier "click".
- Carried: ssh double-execution in this harness (mutations idempotent, no `>`-redirects);
  `permissions.allow` vs resurrected `allowedTools`; otty copy-seeded vs herdr symlinked;
  docs-only PRs report "no checks" by design (but CodeRabbit still stamps).
