---
created_at: "2026-10-23T13:39:39-07:00"
branch: "master"
head: "cab8a90"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
resume_focus: "Report on the 01:30 PT Sat 2026-10-24 pilot run (VIL-391 and VIL-381 part A)"
---
# HANDOFF — 2026-10-23, afternoon (PDT)

A short session after the morning statusline work. Syd, the Mac's Hermes, can now use hal's LM Studio `qwen3.8-27b` as a provider David picks per session. The mergewren handover was mostly done already: only the two failed pilot PRs were still open, and MergeWren has closed them. David chose to keep the statusline's PR-state colors as they are.

## What We Built
- **Syd → hal's LM Studio**: the setup is written down at `docs/reference/hermes-commands.md` (`cab8a90`).
  - The provider is in `~/.hermes/profiles/syd/config.yaml` (`providers.hal`). That file isn't tracked in this repo. A backup sits next to it as `config.yaml.bak-20261023T…`.
  - The key is LM Studio's `david` token. David saved it himself to the profile's `.env` as `HAL_LMSTUDIO_API_KEY`.
  - Tested end to end with `hermes -p syd chat -q … --oneshot --provider hal -m qwen3.8-27b`: it replied in 1m43s, in session `20261023_101727_7c518d`.
- **mergewren handover:**
  - mergewren#80 (VIL-417) had already merged at about 09:39 PDT, and VIL-417 was already Done.
  - #61, #69 and #73 were all already merged.
  - MergeWren closed #79 and #81 unmerged; both show CLOSED.
  - VIL-391 and VIL-381 stay In Progress, because part A runs tonight and part B comes after.
- **Memory:** `agents_atlas_axiom.md` now records the Syd → hal exception, which David chose.

## Decisions Made
- **The statusline's PR-state colors stay red/green.** David's call. This removes item 5 from the last handoff; don't raise it again.
- **Syd uses `qwen3.8-27b`, not `qwen3.6-35b-a3b`.** The 27B is dense and newer, and the pilot trusts it with code. The 35B is a MoE with about 3B parameters active per token. This comparison comes from the models' architecture; nothing on hal measures quality, since hal-bench only measures speed.
- **Opus stays Syd's default, and hal is opt-in.** Syd was set up for tasks that stay fully local. Sending its prompts to hal is an exception David accepted.
- **`context_length: 131072`**, matching Atlas's hal provider. A pilot run on this model hit "Prompt is too long" at 173k.
- **The shared `david` token** was David's choice over a new token per client. Revoking `david` also cuts off Syd.

## What Didn't Work
- **LM Studio tokens can't be made from the CLI.** `lms` has no token command, and the docs show only the GUI. The details are in the doc above.
- **My Syd test calls overlapped a hal-bench speed run.** The "milestone 1 baseline" run on `qwen3.8-27b`, run as `david` on hal, was going at about 10:16–10:19 PDT. LM Studio serves 2 requests at a time, so whatever hal-bench tests ran in that window may be slowed. I didn't tell the hal-bench session.

## What's Next
1. **Report on the 01:30 PT Sat 2026-10-24 pilot run** (VIL-391 and VIL-381 part A), as `david` on hal.
   - Read `~/runs/log/runner.log`.
   - For each run, read `run.json` and run `pilot/timing.py`.
   - If VIL-391 runs out of context again, test the 160k hypothesis and write the result in `pilot/README.md`.
   - Hand any mergewren PRs to the "VIL-317 and VIL-400 pilot merges" session (MergeWren, Remote Control).
2. **Queue part B once each part A has merged:**
   - VIL-391 part B: `codex_delegate._parse_events` and `watch.transient_cause`, plus a grep test for `splitlines`.
   - VIL-381 part B: fix the stale citations, then handle test-name citations.
3. **VIL-515: move `pilot/` into the private repo `villavicencio/hal-pilot`**, after item 1. The steps are on the ticket. Reloading the LaunchDaemon needs `admin`'s sudo password on hal.
4. **Tell the hal-bench session about the 10:16–10:19 PDT overlap**, if David hasn't already, so it can rerun any test that ran in that window.
5. **Carried:**
   - VIL-422: David checks the work Mac for herdr.
   - `ci/op-agent-checks.sh`: refused cases should assert the stub was never called.
   - VIL-431: settings drift.
   - VIL-426: re-measure on 2026-11-05.
   - The pilot branches of the closed #79 and #81 are still on origin. They're deleted only if David approves, because the standing approval to delete branches covers merged PRs only.

## Gotchas & Watch-outs
- **`qwen3.8-27b` is shared** by the pilot (01:30–06:00 PT), hal-bench and now Syd, and LM Studio serves 2 requests at a time. Don't run Syd on hal during the pilot or a hal-bench run.
- **Hermes reads config at startup.** Any Syd session started before a config change needs a restart.
- **The statusline links into this checkout**, so switching branches here changes the live statusline.
- **The mergewren#80 handover is done.** Earlier handoffs listed it as a to-do, so don't redo it.
- **A message to MergeWren over Remote Control** doesn't report whether it was read. Check the PRs' state on GitHub instead.
- **Another session owns #247** (`chore/hal-bench-memory-pull`). Leave it to that session.
