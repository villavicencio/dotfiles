# HANDOFF — 2026-04-17 (afternoon session)

## What We Built

### Shipped to master (4 commits this session)

- **PR #31 `4fbe178` — feat: seed VPS tmux window glyph metadata.** New file `tmux/window-meta.linux.json` with locked mappings for the VPS's static window layout (`ops`=⚙/ocean `#56B6C2`, `logs`=≡/smoke `#4B5263`, `openclaw`=🦀/ember `#D97757`, `tui`=▤/sky `#7DACD3`) under session `main`. Extended `install-linux.conf.yaml:80-88` link block with a single new Dotbot symlink that points `~/.config/tmux/window-meta.json` at the seed file. Darwin `install.conf.yaml` intentionally untouched — Mac's sidecar is still written live by the `tmux-window-namer` skill. Full brainstorm + plan trail in `docs/brainstorms/2026-04-17-vps-tmux-glyph-treatment-brainstorm.md` and `docs/plans/2026-04-17-feat-vps-tmux-window-glyph-seed-plan.md` (plan marked `status: completed` in `219574f`).
- **PR #32 `7f8fda2` — feat: transparent status bar background.** One-line edit in `tmux/tmux.display.conf:33`: `status-style "bg=#031B21,fg=#ABB2BF"` → `bg=default,fg=#ABB2BF`. Makes the bar inherit the pane/terminal background and consistent with `window-style` (which already used `bg=default`). Inner VPS tmux bar now fuses into the outer Mac tmux chrome when nested. Session pills and status-right block keep their own explicit backgrounds, so they still read clearly against the transparent bar.
- **`55ddd52` — docs: compound — sync-vps.yml dry-run previews current HEAD.** New solution doc `docs/solutions/cross-machine/sync-vps-dry-run-previews-current-head.md` capturing the session's footgun: `sync-vps.yml` dry-run runs `./install --dry-run` against the VPS's current working-tree HEAD (not origin/master), because the backing-store safety invariant forbids `git reset --hard` in dry-run. The real preview of what will apply lives in the "Pending commits" entry in `GITHUB_STEP_SUMMARY` from the Fetch step. Reproduction case inline (runs `24578115874` dry-run + `24578272448` apply).

### VPS state

- `readlink ~/.config/tmux/window-meta.json` → `/root/.dotfiles/tmux/window-meta.linux.json` ✅
- All four windows now have `@win_glyph` + `@win_glyph_color` set correctly — applied via manual `bash ~/.config/tmux/scripts/restore-window-meta.sh` (the documented Risk #1 mitigation) rather than forcing a detach on the persistent session from 2026-04-10.
- `tmux show-option -gv status-style` on VPS → `bg=default,fg=#ABB2BF` after `tmux source-file` reload. Live server picked it up in place; no detach required.

## Decisions Made

- **Approach A over B and C for the VPS glyph seed.** Chose a static committed seed JSON + Linux-only Dotbot symlink over (B) an inline `set-hook` block in tmux config, and (C) extending the `tmux-window-namer` skill to be SSH-aware. Rationale beyond YAGNI: the architectural win is that the skill stays purely local (Mac-only, no remote-execution surface), the tmux config stays purely declarative, and Dotbot remains the sole host-aware layer — that three-way separation is worth preserving as the repo grows.
- **First committed host-segmented state file; migration trigger named.** `tmux/window-meta.linux.json` sets a precedent. Rule for the future: **the second host-scoped state file is the trigger to migrate both into `hosts/<os>/`** — not now. Captured in the plan's Risk #3 and surfaced by the architecture-strategist review.
- **Transparent status bar as a global change (both hosts) rather than Linux-only conditional.** Option B would have introduced an OS-branching `if-shell` block in tmux.conf — first precedent of its kind. Went global instead because (a) the change is aesthetically consistent with `window-style "bg=default"` already in the same file, (b) Mac visual is either identical or marginally cleaner depending on iTerm2 transparency, (c) no real downside, (d) YAGNI on the OS-conditional infrastructure.
- **Applied the restore hook manually on VPS instead of forcing a detach.** The `main` session has been attached since 2026-04-10, and `client-attached` doesn't retroactively fire on an already-attached session. Running `bash ~/.config/tmux/scripts/restore-window-meta.sh` directly is less intrusive than `tmux detach-client -a` (which would have kicked any other connected clients).
- **Compound doc scope: one lesson, not many.** Considered compounding (a) ambient-write-path-check rule, (b) `.linux.json` migration trigger, (c) `bg=default` cascade pattern — rejected all three in favor of the single sync-vps.yml dry-run footgun. Others are already captured in the plan/brainstorm, too generic to be useful standalone, or basic tmux knowledge.

## What Didn't Work

- **The `learnings-researcher` agent claimed `restore-window-meta.sh` would overwrite the seed file with live state.** That was wrong — `restore` only reads; `save` is invoked solely by the Mac skill with CLI args (no auto-hook). Caught via direct grep over `tmux/`. Bears the general lesson that subagent claims about file write paths need verification against the source, not trusted wholesale.
- **Attempted to rely on `sync-vps.yml` dry-run output to confirm the new symlink would be created.** It didn't show up, which triggered a brief investigation — all by-design, now documented. Won't happen again.

## What's Next

Carried forward from the previous handoff (still relevant):

1. **Cross-machine sync test on the FedEx work Mac.** Run `./install` on the FedEx Mac to verify the Dotbot v1.24.1 bump, the OS-detect wrapper, and all fixes from recent sessions (SC2218 hoist, deprecated taps, osx/ removal, telemetry flag removal, plus today's tmux status bar change) behave identically. Acceptance: no symlink changes, idempotent second run, Brewfile step completes without deprecated-tap errors.
2. **OAuth secret rotation reminder — 2027-04-14.** Runbook in `docs/solutions/cross-machine/vps-dotfiles-target.md` has the procedure.
3. **Optional follow-ups (no tickets yet):**
   - **Backfill the VPS runbook** with the new sync-vps.yml dry-run semantic (recommended by the compound doc's Prevention section). One-liner under the sync workflow section of `docs/solutions/cross-machine/vps-dotfiles-target.md`.
   - Sidecar rename cleanup for orphaned entries in `~/.config/tmux/window-meta.json` on Mac.
   - Self-hosted OTel collector for Claude Code usage dashboards.
   - VPS OOM regression (out of scope for dotfiles; belongs to openclaw).

## Gotchas & Watch-outs

- **`tmux/window-meta.linux.json` is the first committed host-segmented state file.** If/when a second one is needed (btop? lazygit?), migrate both to `hosts/<os>/` instead of adding another `.linux.json` suffix. Don't cargo-cult the suffix pattern.
- **Do NOT install Claude Code or run the `tmux-window-namer` skill on the VPS.** The skill's `save-window-meta.sh` writes through to `~/.config/tmux/window-meta.json`, which is a symlink into the repo. Any VPS-side skill invocation would mutate the committed seed file. If a remote control plane is ever needed, revisit Approach C from the brainstorm.
- **`sync-vps.yml` dry-run Install step log is NOT a preview.** It runs against the VPS's current HEAD — the per-symlink preview only appears on the full-apply run. Authoritative preview is the "Pending commits" markdown block in `GITHUB_STEP_SUMMARY` from the Fetch step. Full doc at `docs/solutions/cross-machine/sync-vps-dry-run-previews-current-head.md`.
- **Persistent VPS tmux sessions don't auto-pick up config/meta changes.** `client-attached` hook only fires on a fresh attach. After merging + syncing, either invoke the relevant script manually (`bash ~/.config/tmux/scripts/restore-window-meta.sh` or `tmux source-file ~/.config/tmux/tmux.conf`) or detach + reattach.
- **`claude/settings.json` accumulates per-session permission grants.** If you see a bloated `permissions.allow` block in `git diff`, don't commit it — `git checkout -- claude/settings.json`.
- **1h cache is OAuth default in Claude Code 2.1.111.** Don't re-add `CLAUDE_CODE_ENABLE_TELEMETRY=1` "for the cache." The flag is a no-op without `OTEL_*` companion vars.
- **Work Mac runs through Vertex (`CLAUDE_CODE_USE_VERTEX=1`).** Cache behavior and many observations in this handoff are OAuth-specific.
