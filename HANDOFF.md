---
created_at: "2026-10-17T15:34:06-07:00"
branch: "master"
head: "06ebc25"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-10-17, afternoon (PDT)

This session ran 2026-10-14 to 10-16. It finished the `wt` PORT work (#222), then started the **hal Local Coding Pilot**. The pilot's model: Opus 5.5 plans, writes the acceptance checks and reviews; local Qwen on hal does menial tickets overnight as draft PRs that MergeWren reviews. Nothing merges without David. Setup is done and the worker passed a smoke test. Next is building the runner. dotfiles has no open PRs, the tree is clean, and `master` matches origin.

## What We Built
- **#222 (`06ebc25`), VIL-386 Done.** `wt` gives each worktree a dev-server PORT, opt-in with `wt.portBase`. MergeWren finding `64fd18f#2` (a missing `nc` skips the cross-account port check) is deferred to **VIL-401**.
- **davidv.sh `8f7f355`.** The `/ops/parallel-sessions` page covers PORT, and davidv.sh has `git config wt.portBase 3000` set.
- **Linear project "hal Local Coding Pilot"** (P-VIL-11). Its description holds the shape, how quality is measured, and the guardrails.
  - **VIL-394 Done.** Weekly usage baseline: ~$485 API-equivalent, two Obscura sessions were 48% of it, ~25% saving if sessions stayed near 200k. The `usage_week.py` script is in a comment.
  - **VIL-395 In Progress.** Harness and model decision, plus the findings comments. Read its comments before touching LM Studio.
  - **VIL-396** runner, **VIL-397** ticket intake, **VIL-398** two-week verdict (blocked by 394–397).
- **VIL-402** (Dotfiles): context discipline. Trim this repo's 104 KB CLAUDE.md, add an auto-compact threshold, and a fresh-session rule.
- **Pilot secrets on hal, both in `david`'s home, mode 600. Never print them.**
  - `~/.config/hal-pilot/gh-token`: fine-grained `hal-pilot-runner`, expires in 30 days. It covers dotfiles, bryancola.com, browse-gateway and mergewren, with Contents and PR read/write and no Workflows. It gets 404 on davidv.sh and axiom.
  - `~/.config/hal-pilot/lmstudio-token`: `hal-pilot-worker`, with both MCP permissions denied. It can't be blocked from load/unload.
- **Memory** (`memory/`):
  - `hal_accounts.md` now covers LM Studio startup, the `cd /tmp` sudo form, the Screen Sharing gate, `--bare`, and where the secrets live.
  - New `agents_atlas_axiom.md` and `feedback_where_and_as_who.md`.

## Decisions Made
- **Two tiers, both Claude Code.**
  - Opus (`david`'s subscription) writes the brief and acceptance checks, then reviews.
  - The worker is `claude -p --bare --tools Read,Edit,Bash` pointed at LM Studio with `qwen3.8-27b`. The exact env is in the VIL-395 smoke-test comment.
  - `--bare` skips CLAUDE.md, so Opus's brief has to carry the repo rules that matter.
- **The runner runs as `david`, by David's choice (2026-10-16).** The risk is accepted and recorded on VIL-396. I had recommended a separate `pilot` account.
- **The four pilot repos are dotfiles, bryancola.com, browse-gateway and mergewren.** atlas-tools is out: it isn't on GitHub. None of the four has branch protection, and the private ones can't on the free plan. So the guard is that the runner pushes only `pilot/*` branches, enforced by a pre-push hook in its clones.
- **Pilot PRs go to MergeWren**, which also reviews mergewren's own PRs. Keep pilot tickets away from mergewren's review logic.
- **LM Studio stays as it is: no reload, no unload.**
  - Atlas and Axiom both run `claude-opus-5-5` as their main model, and both send side jobs to `qwen3.6-35b-a3b` and `qwen3.8-27b` through provider `hal`.
  - The models are MLX, and MLX ignores `-c`, so a context reduction frees nothing. The ~21 GB above the weights is probably MLX cache.
  - `memory_pressure` showed 38% free.
  - The pilot shares `qwen3.8-27b`. The runner skips the night if free memory is under 20%.
- **No Hunter account exists on hal.** `dscl` lists only admin (501), david (502) and hal (503).

## What Didn't Work
- **A full `claude -p` against LM Studio.** It loads `david`'s global CLAUDE.md, plugins, skills and hooks, and LM Studio never answered the first request ("Request timed out." after 15 min, with retries). `--bare` fixed it in 41 s. A direct curl streaming tool call takes 5 s. The root cause wasn't pinned down: prompt size, or a request field LM Studio stalls on.
- **Reloading the models at 131072 to free memory** was ruled out (MLX, see Decisions). The earlier `--estimate-only` numbers are llama.cpp-style and don't apply.
- **`lms` has no token command.** Tokens are created only in the app, and the app won't open while llmster runs.

## What's Next
1. **Build the runner (VIL-396)** on a dotfiles branch, so MergeWren reviews it. Pieces:
   - Opus writes the brief and checks;
   - the `--bare` Qwen worker in `~/runs/` clones;
   - the `pilot/*` push, with the pre-push hook;
   - a draft PR per run;
   - the `memory_pressure` gate;
   - a launchd schedule;
   - a kill switch.
2. **Pick 3 solved tickets for the bake-off (VIL-395)**, and decide whether the 27B is good enough or the faster `qwen3.6-35b-a3b` (3B active) is worth comparing.
3. **Propose 10–15 queue tickets for David to approve (VIL-397)**, using a `hal-overnight` label.
4. Smaller items:
   - **VIL-402:** context discipline. Do it in a fresh session.
   - **VIL-401:** a small `bin/wt` PR for the missing-`nc` check.
   - **VIL-300:** iTerm2 status over SSH, waiting until David is at the Mac.
5. **Optional:** confirm an Atlas side job still works after the 2026-10-16 llmster restart. Existing tokens should have survived, since ours did.

## Gotchas & Watch-outs
- **Say where and as who on every step**: machine, app or terminal, the account at each hop, and which password a prompt wants. David asked for this explicitly.
- **Reaching the `hal` account:**
  - Use `ssh -t david@hal "cd /tmp && sudo -H -u hal /bin/zsh -lc '…'"`. Without `cd /tmp`, sudo keeps `david`'s cwd, which `hal` can't read, and `lms` fails with a misleading "low max file descriptors" error.
  - `david`'s sudo needs a password, so only David can run these.
- **Screen Sharing to hal:** the first dialog accepts only `admin` or `david`. Sign in as `david`, then switch to `hal`'s session with `hal`'s password. Logging out that `david` desktop session is harmless.
- **LM Studio on hal:**
  - LaunchAgent `dev.hal.lmstudio` runs `~/bin/lms-up.sh` as `hal` (no KeepAlive).
  - Restart it with `launchctl kickstart gui/503/dev.hal.lmstudio`.
  - The server binds 0.0.0.0:1234 and requires a token.
  - Don't unload either model: Atlas and Axiom depend on both.
- **In `david`'s shell on hal, `stat` is GNU.** Use `/usr/bin/stat -f`.
- **Claude Code against LM Studio:**
  - It logs `[claude-code:unrecognized_model]`, which is harmless.
  - Set `CLAUDE_CODE_MAX_CONTEXT_TOKENS` yourself, and leave `ANTHROPIC_API_KEY` unset.
- **The secret classifier blocks printing local secrets into chat.** Test tokens through `$(cat file)` inside the remote command and print only status codes.
- **Don't restart herdr** (standing instruction).
