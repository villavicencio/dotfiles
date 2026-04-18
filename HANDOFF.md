# HANDOFF — 2026-04-18 (afternoon/evening session)

## What We Built

### Shipped to master (15 commits this session — big one)

**Tmux window-tab styling polish (earlier):**
- **PR #31 `4fbe178`** — seed VPS tmux window glyphs via Linux-only Dotbot symlink.
- **PR #32 `7f8fda2`** — transparent status bar background (`bg=default`).
- **PR #33 `cc5b305`** — dim window glyph on inactive tabs (glyph matches title color when not focused, keeps palette color when active).
- **PR #34 `8bd9ae8`** — rename VPS window 4 from `tui` → `OpenClaw` with `\uee0d` / `#FF4500`.
- **`5043e3c`** — fix: PUA glyph stripped by Write tool (discovered bug in Claude Code tool layer).
- **`ac79cc7`** — docs: extend PUA-stripping solution to cover the Write tool, not just Bash argv.
- **`30ef6fe`** — shrink VPS seed to only OpenClaw (user killed windows 1-3 on VPS), add thin space after glyph.
- **`50a252d`** — fix seed key `main` → `vps` to match renamed VPS session (Risk #2 from brainstorm fired).
- **PR #35 `d9475e6`** — blue session-name pill `#2563EB` / white. Renamed sessions: local Mac `main → local`, VPS `main → vps`.

**Local Mac window styling (Home/FedEx/Eagle/Wedding/Dotfiles tabs — sidecar-only, no commits):**
- Home: `\ueea7` + rose `#C98389` + thin space
- FedEx: `\U000F129B` + subdued violet `#9E7BC5` (brand-adjacent, iterated from `#4D148C` → `#7C2FB8` → `#9D4EDD` → `#9E7BC5`)
- Eagle: `\U000F0640` + Eagle brand blue `#0072EF`
- Wedding: `\ue23d` + old gold `#D4AF37` (Gatsby-themed, hosted at davidandbrittanie.com, 8/1 date)
- Dotfiles: `\uf489` + moss `#7A9E5F` (subdued forest / CLI terminal green)

**Claude Code PATH saga (new finding):**
- **PR #36 `944d0ce`** — reorder zshenv PATH: `$LOCAL_BIN:$LOCAL_SHARE_BIN` before `$BREW_BIN`. Standard Unix user-scope-first ordering. Motivated by Anthropic's native `claude` installer putting `~/.local/bin/claude → ~/.local/share/claude/versions/<latest>` (2.1.114) while Homebrew cask was stuck at 2.1.98.
- **PR #37 `adfa624`** — fix: `brew shellenv` in zshrc runs nested `eval path_helper -s` that rebuilds PATH with Homebrew at front, undoing PR #36 in interactive shells. First filter attempt (`grep -v '^export PATH='`) missed it because the clobber is two evals deep. Correct filter: `grep -vE '^eval .*path_helper'`.
- **`60ebbc0`** — compound doc capturing the two-layer fix + debugging recipe at `docs/solutions/code-quality/brew-shellenv-clobbers-path-via-path-helper.md`.

**Work Mac install verification:**
- `./install` on the FedEx Mac initially failed because the `dotbot/` submodule had stale 2022 modifications to `test/test`, `tools/git-submodule/install`, `tools/hg-subrepo/install`. Force-updated with `git submodule update --init --recursive --force`; install succeeded. Carry-forward from yesterday's handoff is now complete ✅.

### Operational events (not commits)

- **VPS went down mid-session** — OpenClaw-gateway cgroup OOM loop cascaded, `kswapd0` + `tailscaled` + `containerd` all blocked >122s, systemd watchdog firing. Hetzner Ctrl+Alt+Del didn't help; hard power-off → power-on recovered. VPS came back up healthy with 5.5Gi free / swap empty / all containers healthy within 18s.
- **Post-reboot cleanup:** restore script re-applied via SSH; session rename + blue pill re-applied; seed file key `main → vps` fix committed so restore finds the right entries; verified `@win_glyph` = `U+EE0D + U+2009`, color `#FF4500` live on the VPS.
- **Post-reboot Coolify "unhealthy":** turned out to be syncthing's healthcheck (probes port 8384 which is disabled by the "scale-only admin UI" hardening); not an openclaw problem at all. Flagged for an openclaw-session fix.

## Decisions Made

- **User-scope bins before Homebrew in PATH** is now the dotfiles convention. Means any tool installed to `~/bin` or `~/.local/bin` shadows its Homebrew counterpart. Documented in `zsh/zshenv:64-71` comment.
- **`brew shellenv` filtered to drop path_helper line** rather than removed entirely. Keeps `HOMEBREW_PREFIX/CELLAR/REPOSITORY/FPATH/MANPATH/INFOPATH` — only PATH clobber suppressed. Documented in `zsh/zshrc:23-29`.
- **Session renames (`local` / `vps`) are durable via tmux-continuum's auto-save**, not config. Continuum saves session names every 15 min and restores on next server start — confirmed working via VPS reboot survival.
- **Blue status pill is always-on** (not focus-conditional). Explored the "only when active" ask; ruled out because tmux has no reliable cross-server focus primitive in nested scenarios. The PREFIX/COPY/SYNC modes keep their own colors and still override.
- **Dotfiles Mac tabs use per-window palette colors drawn from brand/thematic context** rather than strict palette-md discipline. `moss` (Dotfiles), `#9E7BC5` (FedEx), `#0072EF` (Eagle), `#D4AF37` (Wedding/Gatsby) are all off-palette but deliberate. Palette file (`claude/skills/tmux-window-namer/references/palettes.md`) remains the source of truth for the skill itself; manual one-off windows can break the rule with documented reasoning.
- **Rejected Vercel migration for OpenClaw.** Spent a moment exploring since user was frustrated with VPS capacity. Concluded: OpenClaw's architecture (persistent Discord gateway connections, cron scheduler, long-lived agent TUI state) is fundamentally incompatible with Vercel's serverless model. Hetzner is the right platform; the symptom is openclaw-gateway's memory leak, not infra sizing.
- **Claude Code version divergence is upstream-side.** Between-session `/model` picker inconsistencies trace to Anthropic's auto-updater downloading versions to `~/.local/share/claude/versions/` while Homebrew cask lags. PR #36/#37 make the local side consistent; the actual version catalog freshness is upstream's responsibility.

## What Didn't Work

- **First PATH fix (PR #36) alone.** Reordering zshenv PATH was necessary but not sufficient — interactive shells reverted on every init because `brew shellenv` via `path_helper -s` reconstructs PATH two evals deep. Needed PR #37 as a follow-up. Lesson preserved in the compound doc.
- **`grep -v '^export PATH='` as a filter for `brew shellenv` output** — looked like the obvious culprit regex but matched nothing, because the actual PATH export is in a nested eval that the outer grep never sees.
- **Parking newer `~/.local/share/claude/versions/` binaries** to force fallback to 2.1.111 — unsucessful; Anthropic's auto-updater re-downloaded 2.1.114 within minutes, plus the launcher fell to Homebrew 2.1.98 instead of the remaining 2.1.111 (didn't prefer highest semver as I'd assumed). Reverted with `_parked/` → `versions/`.
- **`--model claude-opus-4-7` as a version pin** — my suggestion was wrong; Claude Code 2.1.98 accepts any `claude-opus-4-*` as a family prefix without strict validation (user proved it with `claude-opus-4-70`). The CLI flag is a hint, not a pin.
- **Ctrl+Alt+Del via Hetzner console to recover the OOM-wedged VPS** — didn't help given kernel tasks were blocked. Full power-off → power-on was required.

## What's Next

Carried forward / new:

1. **OpenClaw-gateway memory leak** — not dotfiles work, but the reason the VPS went down today. Belongs in an openclaw session. The symptom-mitigation pattern would be a pre-OOM guard cron that restarts gateway on schedule before it hits 2GB.
2. **Syncthing healthcheck misconfig on VPS** — probes port 8384 (admin UI, hardened off); always-failing. Fix: swap probe to `nc -z 127.0.0.1 22000` (sync protocol port) or remove the healthcheck entirely. Openclaw repo, not dotfiles.
3. **Backfill VPS runbook (optional)** — one-liner in `docs/solutions/cross-machine/vps-dotfiles-target.md` near the sync-workflow section noting the `sync-vps.yml` dry-run semantic from yesterday's compound doc.
4. **Consider removing `claude-code` from `brew/Brewfile`** — now that PATH prioritizes the native installer symlink, the Homebrew cask is redundant baggage and perpetually lags. Would need `helpers/install_claude_code.sh` running `curl -fsSL https://claude.ai/install.sh | bash` on fresh machines. Worth its own PR.
5. **`sync-vps.yml` tailnet ping flakiness** — GH Actions' tailnet join step has failed the ping check 2+ times in a row now. Worth investigating: pin `version:` instead of `latest`, or add a retry, or swap to ICMP-less connectivity check.
6. **OAuth secret rotation reminder — 2027-04-14** (runbook in `docs/solutions/cross-machine/vps-dotfiles-target.md`).

## Gotchas & Watch-outs

- **`brew shellenv`'s path_helper eval is two layers deep.** If you're ever debugging why zshenv's PATH ordering doesn't stick in interactive shells, expand `$(brew shellenv)` all the way down — the culprit is `eval "$(path_helper -s)"` inside. Full writeup at `docs/solutions/code-quality/brew-shellenv-clobbers-path-via-path-helper.md`.
- **Claude Code Write tool strips PUA characters from file content**, same bug class as the long-known Bash-tool argv stripping. Always use JSON `\uXXXX` escapes in committed files, never literal PUA chars. Updated doc at `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md`.
- **`~/.local/bin/claude` is the authoritative CLI entry point now.** Homebrew's `/opt/homebrew/bin/claude` at 2.1.98 is stale and will stay that way until cask maintainers catch up. Don't be surprised that `brew info claude-code` reports "up-to-date" while the actual latest is 2.1.114.
- **VPS tmux seed file is keyed by session name.** If you ever rename the session, update the top-level key of `tmux/window-meta.linux.json` to match, or restore-script lookups silently fall through and windows revert to no-glyph rendering. Risk #2 from the original brainstorm — now documented as a real-world occurrence.
- **Off-palette glyph colors are OK for manual one-off windows** (moss, FedEx-purple, Eagle-blue, Gatsby-gold) but the `tmux-window-namer` skill still only uses palette.md. Don't modify the skill to allow freeform colors.
- **VPS health is fragile post-reboot.** OOM loop can re-manifest within hours if gateway leak recurs. If a future session finds the VPS unreachable again, skip straight to Hetzner power cycle — don't burn time on Tailscale diagnostics if public IP responds to ICMP but SSH banner-exchange times out (classic cgroup-OOM signature).
- **Claude Code session model availability is snapshot-at-launch.** Two sessions on the same machine/binary can see different `/model` picker contents depending on when they fetched the server-side catalog. Not a bug, not a fixable thing — wait for Anthropic's next Claude Code release if the picker is off.
- **`claude/settings.json` still accumulates per-session permission grants.** If `git diff` shows a bloated `permissions.allow` block, don't commit it.
- **Work Mac is Vertex (`CLAUDE_CODE_USE_VERTEX=1`).** Model availability there is region-tier-gated separately. Cache and `/model` behavior observations from OAuth sessions don't transfer.
