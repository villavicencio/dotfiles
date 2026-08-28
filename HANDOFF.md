---
created_at: "2026-08-27T14:58:02-07:00"
branch: "master"
head: "c19807e"
resume_focus: "Two uncommitted files are sitting in the tree and one is a defect: zsh/zshrc line 248 has a cua-driver-rs installer edit with a hardcoded /Users/dvillavicencio path, and it is redundant because zshenv already puts ~/.local/bin on PATH. Delete those three lines, then decide on nvim/lazy-lock.json. Nothing else is pending here."
---
# HANDOFF — 2026-08-27, afternoon (PDT)

A herdr fleet-operations session that started as a routine pickup and turned into building the
tooling the fleet never had. The arc: a documented recovery procedure was found to be wrong,
rewriting it exposed a bug that had been silently degrading panes for weeks, and proving that bug
required two full server restarts — which produced a verified upstream report and a
recovery tool that now handles the whole cycle. Nine commits to master, one new ops SOP, one
GitHub issue filed. Zero PRs — everything here was docs, a new read-only tool, or config hygiene.

## What We Built

- **`herdr/fleet-check.py`** — snapshot/verify/repair for the fleet across a server restart.
  `repair` is the load-bearing part: it rebuilds only panes with **no live agent** and holds the
  rest. The reason is not obvious from the code — after a restart a resumed pane and a bare shell
  are byte-identical in `layout.export` (both lost their command), so the naive "rebuild
  everything the verifier lists" destroys live conversations to fix metadata that only matters at
  the *next* restart.
- **`repair --resume`** (`c19807e`) — rewrites the launch to `claude --continue || claude`. The
  `||` fallback is required, not defensive: verified that `--continue` exits 1 in a directory with
  no prior session, so without it the pane lands at a bare shell instead of an agent.
- **`docs/solutions/`-adjacent: `/ops/herdr-restart`** on davidv.sh — the self-serve restart SOP,
  written to be followed with no agent driving. Corrected twice during the session as evidence
  contradicted it.
- **`/ops/email`** on davidv.sh — Google Workspace setup for `david@davidv.sh`. The load-bearing
  fact is the January 2027 deadline, not the pricing: Gmail removes "Send as" for third-party
  addresses, and Q3–Q4 2026 is already the window where new configurations get restricted.
- **[herdrdev/herdr#3306](https://github.com/herdrdev/herdr/issues/3306)** — the command-loss bug,
  filed with a two-restart reproduction. **Closed `NOT_PLANNED` 17 minutes after filing** by
  `akbash-bot` (same bot that closed #2966): "arbitrary process panes return as new shells" after a
  cold restart is documented behaviour, and keeping declarative commands across restarts is a
  restart-model change → Ideas discussion, not a bug. `fleet-check repair --resume` is the local
  answer; no re-file.
- **`.claude/settings.local.json`** pruned 174 → 91 rules; `CLAUDE.md:841` records why.

## Decisions Made

- **A `*` in a `Bash(...)` permission rule belongs after the subcommand, never mid-command** —
  `CLAUDE.md:841`. David flagged one rule; the audit found ~35 more in the `Bash(cmd *)` space-star
  form, including two that pre-approved arbitrary commands on the VPS.
- **`fleet-check` keys its snapshot diff by `(workspace label, cwd)`, not by any id.** Pane ids
  change on rebuild and — discovered mid-session — `layout.apply` **mints a new tab id** rather
  than reusing the one addressed. Label alone collides (`sites` holds four panes); cwd is the
  project and does not move.
- **`snapshot` merges, never overwrites** (`aad605b`). A pane whose command was already lost reads
  as command-less live, so a plain write destroyed the only record of how to rebuild it — at
  exactly the moment it was needed.
- **No PR to herdr, ever.** Their `CONTRIBUTING.md` auto-closes unsolicited PRs regardless of
  quality or authorship, and has an explicit "Instructions for coding agents" section requiring
  refusal. Bug reports are welcome; analysis and proposed fixes in them are not.
- **The restart SOP lives on davidv.sh/ops, not as a second artifact** — a duplicate SOP is the
  stale twin the shelf exists to prevent.
- **Ruled out:** rebuilding this pane (`w1:t7`) to restore its layout command. Unnecessary —
  `snapshot` carries its command forward, so the next restart makes it a bare shell that `repair`
  fixes automatically.

## What Didn't Work

- **The documented pane-recovery recipe was too blunt.** `CLAUDE.md` said to rebuild a degraded
  pane with `layout.apply`. That is right only when `layout.export` shows *no* `command`; when the
  command is present and only the process fell back (clean ssh detach), `herdr pane run <pane-id>
  'exec <command>'` reattaches without destroying the pane. Split into two cases at `CLAUDE.md:492`.
- **"Names are lost when a pane is recreated" was too narrow.** The binding releases when the agent
  *process* dies — verified by reusing pane `w8:p6` and still getting `name: null`.
- **#2966 was never a rare boot-race.** Both restarts dropped the command from **all 16 panes**,
  local and remote alike. The original issue was closed `not_planned` by a rate-limit bot that
  never triaged it.
- **Following the SOP left every rebuilt pane blank**, which reads exactly like lost context. It
  is not — transcripts were intact on disk the whole time (skills 1,998 messages, borealis 1,404).
  This was the gap `--resume` closes, and it should have been flagged before rebuilding six panes.
- **A guess that the browse-gateway tunnel had self-disabled was wrong** — the keeper script
  explicitly never does that any more. The tunnel dropped and recovered on its own; what did not
  recover was the MCP client, which connects once at session start and never retries.
- **A guess that `herdr-blank-state.sh` was dangling was wrong** — the hook runs fine. The error
  seen in a pane was replayed scrollback from an old session that started while it *was* broken.

## What's Next

1. **`zsh/zshrc` has an uncommitted installer edit that needs deleting** — three lines at the end
   added by the cua-driver-rs installer, with a hardcoded `/Users/dvillavicencio` path. It is also
   redundant: `zshenv` already puts `~/.local/bin` on PATH. This is precisely the "Post-installer
   audit" case in `CLAUDE.md`.
2. **`nvim/lazy-lock.json`** is also uncommitted (3 plugin bumps) — commit or revert deliberately.
3. **[#3306](https://github.com/herdrdev/herdr/issues/3306) is closed `NOT_PLANNED`** (bot triage,
   2026-08-27 15:15Z). If the ask is ever pursued upstream it is an [Ideas discussion](https://github.com/herdrdev/herdr/discussions/new?category=ideas);
   do not re-file, do not open a PR. Decide instead whether `claude --continue || claude` becomes
   the fleet pane-template default (item 5).
4. **The email setup has not been started** — `davidv.sh` still has no MX/SPF/DKIM/DMARC. The
   runbook is at `/ops/email`; it is a human job (Workspace signup, DKIM console toggle).
5. **Optional:** adopt `claude --continue || claude` as the fleet pane template default rather than
   a `--resume` flag. It would make every restart self-restoring, but it deviates from the
   documented standard, so it is David's call.

## Gotchas & Watch-outs

- **`brew services restart herdr` never upgrades** — it restarts the installed version. Upgrade
  and restart are separate steps, which is useful: `brew bundle install` leaves panes running.
- **Run the restart from a terminal outside herdr**, or it kills the shell mid-command.
- **`--continue` takes the most recent session in a directory** — revive a blank pane *before*
  typing into it, or the new session becomes the most recent one. A pane never typed into has
  written no transcript at all, which is why this worked cleanly here.
- **Every id churns on rebuild.** Pane ids and tab ids both change, so a rename list printed
  before `repair` is stale — re-run `verify` after.
- **Large sessions show a "Resume full session as-is" dialog** on resume. A keypress, not a hang;
  do not rebuild the pane.
- **`layout.export` ignores `workspace_id`** and returns the focused workspace — address by
  `tab_id` or you get believable data for the wrong target.
- **The MCP client does not retry.** If `browse-gateway` tools are missing, the tunnel may already
  be healthy; check `lsof -nP -iTCP:8080 -sTCP:LISTEN` before touching launchd, and start a new
  session rather than restarting anything.
- **Five jump keys had been dead for weeks** (`argus`, `borealis`, `melos`, `obscura`, `skills`) —
  they resolve via `herdr agent focus <name>` and those agents were unnamed. All 11 resolve now;
  `fleet-check verify` catches this going forward.
