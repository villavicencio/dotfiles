---
created_at: "2026-10-09T21:15:19-07:00"
branch: "master"
head: "ef106b3"
worktree: "/Users/dvillavicencio/Projects/Personal/dotfiles"
---
# HANDOFF — 2026-10-09, evening (PDT)

A long session that started from one question: was Claude Code running from a Homebrew cask instead of the native installer? It was, and fixing that led into a dotfiles PATH bug on desk and server, MergeWren's file-type gap, and setting up `bryancola.com` as a Claude Code project on hal. Every dotfiles PR from the session is merged, no dotfiles PR is open, and both hal accounts (`david`, `hal`) are on master at `03f4ef3` or later.

## What We Built
- **#208 (`9f37dfb`): PATH order.** `zsh/zshrc` and `zsh/zprofile.server` re-source `zshenv` after `brew shellenv`, so `~/.local/bin` beats Homebrew. `dot doctor` (`bin/dot`) fails when `claude` doesn't resolve to the native install, or when `~/.local/bin/claude` doesn't point into `~/.local/share/claude/versions/`.
  - Write-up: `docs/solutions/runtime-errors/brew-shellenv-path-prepend-shadows-native-claude-2026-10-08.md`.
  - The `claude-code@latest` cask was uninstalled on the Mac.
- **#209 (`f96873a`): `zsh/functions/ssh_reset_modes.sh`.** An `ssh()` wrapper that clears mouse, focus, bracketed-paste and kitty-keyboard modes after a dropped session. It leaves the alternate screen with `\e7` then `?1049l`. That combination is correct in both cases only because iTerm2 keeps one saved cursor per screen (`VT100Terminal.m`, its savedCursor function and the case 1049 branch). Don't "simplify" it to plain `?1049l` or `?1047l`.
- **#210 (`8141a95`): `bun`** in `brew/Brewfile` and `brew/Brewfile.server`. The compound-engineering and vercel plugins need it.
- **#207 (`03f4ef3`): drag-to-copy on hal** (`tmux/local.server.conf`, `tmux/scripts/clean-copy.sh`).
  - The bindings pass `#{selection_start_x/y}`, `#{selection_end_x/y}` and `#{rectangle_toggle}`; tmux 3.7c expands formats in `pipe-no-clear`.
  - Two review mediums were declined as an inherent trade-off (see the PR body).
- **Docs straight to master:**
  - `f901c1b`: review-stack `partial` verdicts and MergeWren 0.4.0's inline threads.
  - `ef106b3`: an installer that appends to `.zshrc` edits the repo's `zsh/zshrc`.
- **Linear, MergeWren:**
  - VIL-316 (the `<base>.<suffix>` file-type gap) is Done; David deployed it as MergeWren 0.4.0.
  - VIL-325: commit the bryancola.com adoption record properly.
  - Epic VIL-326, onboarding parity with CodeRabbit, with children VIL-327 to VIL-330.
- **Linear, dotfiles:** VIL-315 (desk non-interactive login shells still get `path_helper`'s order) is open.
- **bryancola.com** (private repo `villavicencio/bryancola.com`; Linear project P-VIL-9, VIL-320 to VIL-324):
  - Phase A is done: `site/` is byte-identical to production deployment `dpl_FtWQkL4RoF4mHazmUbLCSXHuT41D`, tag `v1.0.0`.
  - The hal session is set up: clone, plugins, the `linear` MCP, AGENTS.md, CLAUDE.md and HANDOFF.md. The latest is `71244e2`.
  - The plan is in Proof as "Plan: 2026-10-09 bryancola.com migration to hal". Its link is in the Linear project, and David has the token link.
- **Machine-local, not in the repo:**
  - The Mac's `~/.ssh/config` gained `Host bryancola`, a RemoteCommand that attaches tmux session `bryancola` running Claude Code. The backup is `~/.ssh/config.bak-20261009`.
  - On hal, `david` and `hal` each load iTerm2 shell integration from `~/env.sh`.
  - `david` got a hand-made `~/.config/tmux/scripts/clean-copy.sh` link, the same one `base.yaml` defines.

## Decisions Made
- **Claude Code is the native install only**; the cask stays uninstalled. It was hand-installed 2026-09-22 and topgrade kept it updated.
- **David doesn't use herdr now.**
  - bryancola uses `ssh bryancola` with tmux on hal instead of a herdr pane.
  - #183 and #184 (herdr retirements) were closed unmerged, with their branches kept.
  - The memory index has a warning about this on the herdr-admin entry.
- **bryancola.com:**
  - Production is the fidelity target.
  - It's worked on as the `david` account on hal.
  - Linear and Claude Design log in on hal.
  - No Obsidian vault.
  - The old Forge `graceful-pine`, its vault and the brief repo get archived, not deleted (Phase E).
  - **The site is being rebuilt on a real framework tonight.** The fidelity rule becomes pixel parity against the v1.0.0 deployment URL, which is public and identical to production. David decided the plan rewrite wasn't needed.
- **MergeWren, three rules:**
  - Manual runs need the watcher's environment: `CODEX_HOME=~/.codex-mergewren` (the gitleaks path issue is now fixed on hal by #208).
  - Never commit in its live folder `~/Projects/review-stack`; ticket work happens in worktrees.
  - In dotfiles, merge readiness means no high or critical finding left unfixed. Mediums can be declined with reasons in the PR body.
- **Machine-specific shell lines go in `~/env.sh`, never in the repo's `zshrc`** (now in CLAUDE.md and AGENTS.md).

## What Didn't Work
- **The old `grep -v path_helper` filter on `brew shellenv`** did nothing after Homebrew 7 changed shellenv to a plain `export PATH=` prepend.
- **On #209:**
  - Plain `?1049l` moves the prompt after a failed login, because 1049l always restores the saved cursor.
  - Plain `?1047l` leaves the prompt wherever the full-screen program's cursor was.
- **On #207:** the "line 1 can gain spaces when it's no deeper than the deepest indent below it" rule pasted spaces that were never selected (`3f2c5ab#1`). The final rule is that line 1 only ever loses spaces.
- **Running `review-stack adopt` from a plain `hal` shell** fails preflight: Homebrew's gitleaks comes first on PATH, and Codex reads the dotfiles `~/.codex/AGENTS.md`.

## What's Next
1. **Check gitleaks as `hal`.** Run `which -a gitleaks`; `/Users/hal/.local/bin/gitleaks` should come first now that `hal`'s clone is on master. David hadn't confirmed it yet.
2. **VIL-325:** in a MergeWren session, move the approved record from the live folder onto a ticket branch, add the plan decision, open a PR, then do the `--no-ff` merge. Keep the record in the live folder until that merge; reviews depend on it.
3. **bryancola.com:** the hal session drives it (`ssh bryancola`, then `/pickup`). The framework rebuild changes the MergeWren record, so re-draft it with `adopt --replace-pending` once real lint and tests exist (noted in VIL-325).
4. **VIL-315:** decide how desk non-interactive login shells (`zsh -l -c`) get zshenv's PATH order.
5. **Phase E** of bryancola, after its Gate E: archive `graceful-pine`, `~/Obsidian/graceful-pine`, `~/Projects/bryancolaphotography.com` and `~/Downloads/deploy`. David confirms each move.

## Gotchas & Watch-outs
- **Uncommitted, not from this session:** `iterm/profile-dynamic.json`, `nvim/lazy-lock.json` and `.agents/`. They're David's; leave them alone. They also mean `/handoff` can't auto-commit.
- **MergeWren raises a new medium on almost every push.** A good place to stop is when only medium findings remain and they're edge cases of a trade-off you've chosen. Decline them in the PR body and resolve the threads. With 0.4.0 the unresolved-threads check has to be empty before merging.
- **hal accounts:** `ssh hal-svc` gives a shell as `hal`, and `david` can't read `/Users/hal`. Never touch Hunter's account. Name the account on every hal command.
- **iTerm2 shell integration switches itself off inside tmux** (`TERM=tmux-256color`), so it does nothing inside `ssh bryancola` sessions.
- **The herdr `claude-code` shim** (`~/.local/bin/claude-code`, `~/.local/libexec`) isn't installed on this Mac. Fine while herdr is unused.
- **`zsh`'s `=` expansion** breaks `echo "=== x"` in shell snippets ("== not found"). Use `--` separators.
