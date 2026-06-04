# HANDOFF — 2026-06-04, late afternoon (PDT)

Continuation session that shipped a batch of Rust-CLI shell QoL changes plus a CI
fix, then spent a long stretch debugging why tmux window 7's status-bar tab wasn't
clickable. The window-7 issue was ultimately traced to **PR #90 (the bell-style
change)** and **resolved by the user directly** — do not re-open it.

## What We Built

**Merged this session:**
- **#84** `feat(shell)` — adopt **zoxide + eza** (zoxide `z`/`zi` init in zshrc not lazy-loaded; eza overrides the `ls` family, both guarded by `command -v`). Closed #81.
- **#86** `fix(install)` — dropped 3 stale `claude/commands/{reddit,critique,twitter}.md` `link:` entries from `install.conf.yaml` that broke the **macOS CI leg** (Linux passed; separate config). Includes the compounded learning `docs/solutions/cross-machine/dotbot-stale-link-darwin-linux-config-asymmetry.md`.
- **#87** `fix(zsh)` — hardened the NVM default-node probe: `command ls … | sort -V | tail -1` (decoupled from the `ls` alias; version-sort picks true highest semver). Closed #85.
- **#83** `docs` — branch + PR workflow adopted as the repo default.

**Open PRs (ready, awaiting merge):**
- **#88** `[feat/delta-git-pager]` — delta as the diff/show pager (minimal swap: replaces diff-so-fancy, keeps `core.pager = vim -` for log). Verified locally.
- **#89** `[feat/atuin-history]` — atuin for `^R` history + opt-in hosted sync; retires hstr (`hh` → atuin function in `zsh/functions/hh.sh`). **Closes #82.**
- ~~**#90** (bell-style)~~ — **closed and branch deleted this session.** It was the cause of the window-7 click breakage; the bell-style change is fully discarded. master keeps tmux's default `reverse` bell pill.

**Other:** synced the redesigned statusline to the Axiom VPS via its dotfiles clone; wrote an auto-memory for that pull-path.

## Decisions Made
- **delta:** minimal scope only — diff/show through delta, `core.pager = vim -` retained for log/etc. CLAUDE.md "intentionally left as-is" note updated to reflect the split.
- **atuin:** adopt + **hosted `api.atuin.sh`** sync, **personal Mac only** (work Mac stays unregistered → local-only, corporate history never leaves the device). `--disable-up-arrow` (keep zsh's Up) and `--disable-ai` (atuin 18.x binds `?` to an AI feature by default).
- **hstr retired** in favor of atuin; `hh` is now an atuin-backed function.
- **PR #90 abandoned:** a non-`reverse` `window-status-bell-style` breaks tab-clicking for belled windows. Keep tmux's default `reverse` bell pill — it's harmless and correct.

## What Didn't Work
- **PR #90's themed bell-style is the root cause of "window 7 tab not clickable."** Empirically: with `window-status-bell-style "reverse"` (default) the tab clicks fine; with **any** non-reverse override (`fg=#D97757,bold` *and* `fg=#D97757` without bold) it breaks. It is **not** the `bold` specifically — it's the override itself interacting badly with the styled Nerd Font glyph on a belled window's tab. **Do not re-attempt a themed bell-style.**
- **Long list of wrong turns on window 7 — do not repeat:** glyph-width drift (tested swapping window 7's 4-byte glyph to 3-byte — no fix), stale client mouse-state (detach/reattach — no fix), multiple-clients/size desync (single client, correct 316 size), and an extended **screen-width / off-screen red herring** (the laptop's narrow display confounded the click-coordinate measurement and sent the debug down the wrong path). The user's first instinct — "stash #90 and test" — was correct; that's what isolated it.

## What's Next
1. **Merge #88 (delta) and #89 (atuin)** — both ready; #89 closes #82.
2. After #89 merges: run **`atuin register -u <user> -e <email>` on the personal Mac only** to activate sync (save the printed encryption key). Leave the work Mac unregistered.
3. *(Optional)* recurring SSH-disconnect "mouse-garbage" — a one-keystroke `fixmouse` recovery (binding or alias wrapping the `\033[?1000l…1006l` reset) was offered but not built.

(The bell-style / window-7 work is fully discarded — #90 closed, branch deleted, master clean. Nothing to do there.)

## Gotchas & Watch-outs
- **Window 7 click issue: RESOLVED, and the cause (a themed `window-status-bell-style`) is fully discarded (#90 closed, branch gone).** Do not re-attempt a themed bell-style — *any* non-`reverse` value breaks tab-clicking for belled windows. master keeps the default `reverse`.
- ⚠️ **Live tmux state left mid-debug:** during the window-7 chase, mouse mode was toggled off/on and `MouseDown1Status` / `MouseDown1Pane` were rebound then restored to defaults. The user reported **the right pane can no longer highlight/select text** — likely a side effect of this live mouse-state churn. **None of it was persisted to config** — it's server-level live state. A clean reset is a fresh tmux server (`tmux kill-server`, *loses running sessions*) or a careful mouse re-init; or it may already be resolved by the user.
- Statusline (`claude/statusline-command.sh`) unchanged this session; existing traps still apply (octal glyph encoding, `0x1F` jq-join byte, two intentional `SC2059` disables).
- Axiom VPS sync (statusline / global CLAUDE.md only): `ssh root@openclaw-prod 'sudo -u axiom git -C /home/axiom/.dotfiles pull --ff-only'`. zsh changes (eza/zoxide/atuin) do **not** apply there — axiom's shell is bash and those tools aren't installed on the VPS.
