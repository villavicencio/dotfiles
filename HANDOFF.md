---
created_at: "2026-09-25T16:22:05-07:00"
branch: "master"
head: "6a136f5"
---
# HANDOFF — 2026-09-25, late afternoon (PDT)

Two days on the Windows gaming PC (Ryzen 5800X / RTX 3070). On 2026-09-24 it became the repo's third target (#186/#187), and WSL became the active Linux target (#188). Then an unattended backlog run cleared every agent-workable Dotfiles ticket in Linear: fresh subagents in separate worktrees, one PR per ticket, merged one at a time. Midway through, David switched the reviewer from CodeRabbit to his own **review-stack**. This session was run from the PC, in `C:\Users\Loft\Projects\Personal\dotfiles`. Everything is merged; master is clean at `6a136f5`.

## What We Built

**Merged PRs (2026-09-24 → 25), all squash-merged:**
- **#189 (VIL-149):** `helpers/install_packages.sh` Linux branch runs `set -euo pipefail` and an `apt_install` helper that retries once after `apt-get update`, so a failed apt install no longer prints "installed successfully".
- **#191 (VIL-146):** Linux git overlay. `git/gitconfig` includes `~/.config/git/gitconfig.platform`. `linux.yaml` links that path to `git/gitconfig.linux`, which resets `credential.helper` and uses only `/usr/bin/gh` for github.com, with `core.pager = less -FRX`. The Macs are unchanged. apt also installs `git-delta`, `vim` and `less`. The gh apt install now keys on `/usr/bin/gh` itself.
- **#190 (VIL-150):** `windows/claude-settings.json` is a hook-free Windows settings seed: the Mac file minus 9 tmux/herdr hooks, `preferredNotifChannel: iterm2` and 4 brew/tmux allow rules, and no added rules (verified).
  - `install.ps1` seeds `~/.claude/settings.json` only when it's absent (temp file plus exclusive move), and links `~/.claude/statusline-command.sh`.
  - `claude/statusline-command.sh`: `~` shortening on Windows via `cygpath`, `printf` instead of `echo` (dash was mangling `\\`), and `jq -j` (a CR from jq.exe).
  - `report_drift.sh` and `install_claude_settings.sh` target the Windows file under Git Bash.
- **#192 and #199 (VIL-153):** `windows/tweaks.ps1` is an opt-in, data-driven script, not called by `install.ps1`. It covers mouse acceleration off (via `SPI_SETMOUSE`), Game Bar background capture off, GPU scheduling on [admin], Windows Time from time.windows.com [admin], the Terminal default profile set to PowerShell 7, and **Game Mode on** (`AutoGameModeEnabled=1`, added by #199).
  - #199 also hardened the Terminal edit: it picks the install that's running, uses a comment-aware JSONC scan for the top-level `defaultProfile`, and does a locked, atomic write through `CreateFileW` P/Invoke.
- **#193 (VIL-152):** Neovim 0.12.5.
  - Windows: winget `Neovim.Neovim` plus a `%LOCALAPPDATA%\nvim` link and `windows/install_nvim.ps1`.
  - Linux: the official tarball into `~/.local`, sha256-checked, with no sudo.
  - Also fixed a bug on every platform: lazy.nvim's first launch rewrote about ⅓ of `nvim/lazy-lock.json`. The helpers now snapshot and restore the pins and verify them with `helpers/nvim_verify_lock.lua`.
- **#194 (VIL-151):** a `windows` job in `.github/workflows/install-matrix.yml` on `windows-2025`, with checks W1–W9:
  - W1: LF-only checkout.
  - W2: parse and PSScriptAnalyzer (settings in `ci/PSScriptAnalyzerSettings.psd1`).
  - W3: every winget ID resolves.
  - W4: the dry run mutates nothing.
  - W5: the `-SkipPackages` apply, then links, stubs and the settings seed.
  - W6: the profile loads.
  - W7: a second run is idempotent.
  - W8: gitleaks blocks a fake token.
  - W9: the #187 autocrlf regression.
  
  `EXPECTED_LINKS` must match `install.ps1`'s `$links`.
- **#196:** follow-up to #194. winget is a hard prerequisite (no fallback, so no false green). The nvim bootstrap is always asserted, W6 fails if starship or zoxide isn't on PATH, and W1/W9 also reject `w/mixed`.
- **#195 (VIL-154, CI half):** the Linux CI container is Ubuntu 26.04, `ghcr.io/villavicencio/dotfiles-ci-ubuntu@sha256:0fe49237…`, built from `ubuntu:26.04@sha256:da6fc2be…`. `publish-ci-image.yml` tags `:26.04`; the `:24.04` tag was never touched.
- **#197 (VIL-155):** `migrate_claude_settings.py` treats MSYS Python as Windows. `report_drift.sh` and `--capture` fall back to `uv run --no-project --quiet python -` when there's no working Python, and look it up only when a comparison actually runs.
- **#198 (VIL-156):** both nvim helpers exit 1 unless nvim's config dir resolves to the repo's `nvim/`, and `install.ps1` skips the helper if the link isn't the repo's. The macOS `brew upgrade` exit status is now reported.

**Direct doc commits to master:**
- `4186b64`, `849d612`, `a75c927`: review-stack is the reviewer, and the rules for reading its verdicts.
- `69c6fd4`: gh needs the `workflow` scope on the PC.
- `b459196`: nvim guard wording.
- `6a136f5`: WSL is on 26.04.

**On the PC itself (outside the repo):**
- **WSL reinstalled on Ubuntu 26.04.1:** `Ubuntu-26.04` is the default; `Ubuntu-24.04` was unregistered, freeing 2.95 GB. David ran `./install` under **sudo-rs 0.2.13**. Verified:
  - login shell zsh;
  - 27/27 nvim pins;
  - `/usr/bin/gh` as the only github.com credential helper;
  - `dot doctor` 0 fail / 4 warn;
  - `dot bench` median 184 ms.
- **PC cleanup (2026-09-24):**
  - removed the ASUS leftovers (the AsIO drivers were moved to `C:\Users\Loft\Backups\2026-09-24-cleanup\asus-system-files`);
  - Resizable BAR on;
  - W32Time syncing;
  - Compound Engineering plugin installed;
  - status line wired into `~/.claude/settings.json` (by hand);
  - `gh auth refresh -s workflow` done.

**Linear:** VIL-146, 148–156 are Done. Filed: **VIL-157** (Linux has no Node or uv). **Open:** VIL-157, and VIL-82 (blocked upstream).

## Decisions Made
- **The Windows layer is PowerShell (`install.ps1`), not Dotbot.** WSL is a separate clone inside the Linux filesystem, not `/mnt/c`.
- **Reviewer:** review-stack for PRs #190 and later (David, 2026-09-24).
  - It reviews every new head automatically and posts one comment tagged `review-stack:head=<sha>`.
  - Merge when the current head's review has no high or critical finding that's neither fixed nor waived by David.
  - CodeRabbit is optional input only; don't re-trigger `@coderabbitai`.
  - Documented in the repo `CLAUDE.md` / `AGENTS.md` under "Branching & pull requests".
- **David's stopping rule for fix rounds:** fix whatever would break a real install or give a false-green CI run; mention the rest, don't chase it round after round. Unfixed medium and low findings are recorded in each PR's body ("Review status at merge") or ticketed.
- **Waivers by David:**
  - #197's high finding: uv may download a Python for `dot drift` on a PC with no Python. That's intended, since uv was his choice over adding a Python to `packages.json` or a Python-free rewrite.
- **Choices by David:**
  - Game Mode is recorded (on).
  - The drift check's Python comes via uv.
- **Windows CI does not run the full `winget import`.** The package list is a gaming PC's (Steam, Rockstar …). W3 checks that the IDs resolve, and the job installs only gitleaks, uv, starship, zoxide and Neovim.
- **`tweaks.ps1` records only settings already present on this PC.** Running it here is a no-op except for Game Mode, which writes `AutoGameModeEnabled=1` the first time.

## What Didn't Work
- **CodeRabbit on the free plan** (1 review/hour, a manual trigger for repos under 10 stars) couldn't keep up with a multi-PR run, which is why review-stack replaced it.
- **Unbounded review-stack fix rounds didn't converge** on #190 and #193: each round's new code drew the next critical finding. Budget 2 rounds, fix minimally, then escalate to David.
- **Merging on a clean re-run after an interrupted review-stack run** (#194) missed 3 findings that were in the interrupted run's draft. They landed later as #196. The rule is in CLAUDE.md now: ask David about the draft first.
- **Dockerfile-only CI image change:** a `ci/Dockerfile` bump alone tests nothing. The `linux` job runs a digest-pinned GHCR image built by `publish-ci-image.yml`, so a release move needs the Dockerfile, the publish tag, a `workflow_dispatch` and the digest pin together (that's how #195 was done).
- **Driving WSL checks with `zsh -l`:** it isn't interactive, so the nvm lazy loader is absent and `node` looks missing. Use `zsh -i`.

## What's Next
1. **VIL-157:** decide whether Linux should install nvm/node and uv. `install_nvm.sh`, `install_node.sh` and `install_uv.sh` are wired only in `dotbot-conf/darwin.yaml` lines 28, 29 and 35. If yes, check the helpers' Linux paths, add CI post-apply assertions (in `zsh -i`), and keep bench under 300 ms.
2. **Two older open PRs (herdr retirements, Mac-side), neither touched this session:**
   - **#183** `chore/herdr-retire-axiom`, created 2026-09-02, has **2 unresolved review threads** and unknown mergeability.
   - **#184** `chore/herdr-retire-atlas-tools`, created 2026-09-03, is CLEAN with 0 threads.
   
   Both predate the review-stack switch, and #183 needs its threads triaged. Do these from the Mac, where herdr lives.
3. **David, whenever:**
   - Run `pwsh -File windows/tweaks.ps1 -DryRun`, then a real run, from an elevated pwsh. The first real run writes Game Mode=1 and is the first-ever live test of the set path.
   - Optionally adopt the new Claude settings seed on this PC; the steps are in #190's body. Skipping it is harmless.
   - `gh auth login` inside WSL, only if you'll push from WSL.
4. **Optional:**
   - Consider simplifying the Terminal `defaultProfile` edit in `tweaks.ps1`. It's about 270 lines, with P/Invoke, for one value; check whether the Terminal fragment `windows/terminal/dotfiles.json` can set the default profile instead. Unverified.
   - Re-pin `install-matrix.yml` to the master-built `:26.04` digest.
   - Delete `C:\Users\Loft\Backups\2026-09-24-cleanup` after about a week without problems.

## Gotchas & Watch-outs
- **review-stack verdicts:**
  - `failed`, "NOT COMPLETE" or "Incomplete review" means *not reviewed*, even if it shows "0 findings ✅".
  - Seen causes: a held run lock (#192), and the connector tripwire on the text `github_` anywhere in the diff (#194's gitleaks test).
  - Atlas re-runs the same head. Don't push a dummy commit to force a retry.
- **The gh token needs the `workflow` scope** to push anything under `.github/workflows/`. It now has it. Composite actions under `.github/actions/` don't need it.
- **The auto-mode classifier blocks agents from writing `~/.claude/settings.json`.** It also once blocked a subagent message about switching reviewers, as a "CI bypass", until David confirmed in-session.
- **`gh pr merge --delete-branch` can't delete a local branch that an agent worktree holds.** The merge still succeeds. Clean up with `git worktree unlock/remove`, then delete the branch.
- **Subagents share the session scratchpad:** give scratch files a per-ticket prefix. One agent deleted another's `review.md`.
- **Chained conflicts:** PRs that touch `install.ps1`, the CLAUDE.md/AGENTS.md step lists or `helpers/install_packages.sh` conflict in a chain. Merge one at a time and bring the next up to date with master (`git merge --no-ff origin/master`) before its final review.
- **The Bash tool collapses `\\` in inline command text.** Feed Windows-path JSON through a file written with the Write tool. Also, `wsl.exe` output is UTF-16, so set `$env:WSL_UTF8=1` before filtering it.
- **Flaky macos CI:** `brew bundle` once failed downloading the `git-credential-manager` cask; a re-run passed.
- **`tweaks.ps1` untested paths:** the registry, mouse and time `set` paths have never run live, and the Terminal `set` path has run only against scratch copies.
