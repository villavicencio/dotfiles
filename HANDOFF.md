---
created_at: "2026-10-02T12:41:20-07:00"
branch: "master"
head: "1c415df"
resume_focus: "PR #203 merged (1c415df). Server profile follow-ups are VIL-280 (tmux local.conf collision + lows). First real server install on hal is Atlas's, from the migration runbook."
---
# HANDOFF — 2026-10-02, early afternoon (PDT)

**Update 13:3x PDT (Atlas):** PR #203 was squash-merged by David's decision as `1c415df` with the `partial` review-stack verdict (the four `*.server` files are outside its file-type policy; read by hand). The open findings are Linear VIL-280. The rest of this handoff describes the branch state at `c01e169`.

Worked Atlas's work order (`../server-layer-work-order.md`, decision D9 of the hal migration, scope approved by David): a `DOTFILES_PROFILE=server` install profile for `hal`, the headless Mac mini. This ran from a fresh clone at `~/Projects/dotfiles-wt/server-layer` on the VPS, not on hal; per the work order, nothing was run on hal. PR #203 is open and CI is green. Merge is Atlas's and David's call.

## What We Built
- **PR #203** (`feat/server-layer`, 5 commits; RED `9ae22a1` → GREEN `730604d` → 3 fix commits). The PR body holds the full design table, the dry-run output, the hal pre-flight list and the "first real run changes" list.
- `install`: profile selection. `server` is macOS-only and fails fast without Homebrew at the `uname -m` prefix. It runs base.yaml with `--except clean`, then `dotbot-conf/server.yaml`.
- `dotbot-conf/base.yaml`: server-only branches. The zshenv backup (a symlink is moved aside), no `~/.config/nvim` link, and the `~/.config/tmux/local.conf` link, which must come **before** the TPM step.
- `brew/Brewfile.server` (28 formulae), `git/gitconfig.server`, `zsh/zprofile.server`, `tmux/local.server.conf`.
- `ci/server-profile-checks.sh` (static/seed/post/launchagents/snapshot) and the `macos-server` job in `install-matrix.yml`. The post-apply composite is profile-aware (R8 server branch, R9 skip, new R10).
- `bin/dot`: check and doctor know `server.yaml`; `DOTFILES_PROFILE=server dot doctor` checks Brewfile.server.
- CLAUDE.md and AGENTS.md: a "Server profile (`hal`)" section and the machine-table row.

## Decisions Made
- **rc chain via `$ZDOTDIR/.zprofile` (`zsh/zprofile.server`)**, not either option the work order offered. `~/env.sh` is interactive-only, and a guarded block in the shared zshrc would fire on desk Macs that have `~/.orbstack` or `~/.lmstudio`. Flagged as a deviation in the PR.
- **zprofile re-sources zshenv**: macOS `/etc/zprofile` runs `path_helper`, which puts `/etc/paths` first in every login shell. CI caught `~/.local/bin` landing behind `/opt/homebrew/bin`.
- **Keep TPM, on a private socket.** The reason was corrected mid-session: TPM's `install_plugins` doesn't `source-file` into a live server. It *reads* `@tpm_plugins` from it, so a config-less live server makes it abort and the install fail.
- **continuum-boot off on server.** With boot on, any tmux server that loads continuum writes `~/Library/LaunchAgents/Tmux.Start.plist`.
- **Keep the Codex AGENTS.md link; skip every `~/.claude` link.** The VPS `~/.claude` has regular files at `CLAUDE.md` and `statusline-command.sh`, so linking them would fail.
- **`--no-upgrade` for brew bundle** on the server.
- Fix-round budget: 2 rounds plus one false-green fix (David's stopping rule), then stop and report.

## What Didn't Work
- My first explanation of the TPM hazard ("reloads the config into a live server") was wrong. A control run disproved it, and the comments and docs were corrected in `c68cee6`.
- The first `macos-server` run failed: `.zshenv` was in the unchanged-file hash list, and the PATH order broke in login shells. Both are fixed.
- A `status-right` probe for "continuum loaded" is unreliable, because continuum skips it when another tmux server runs. The check uses tmux-resurrect's key bindings instead.

## What's Next
1. **Atlas/David: review and decide the merge of #203.** Do not merge from an agent.
2. **Unfixed review-stack findings on `c01e169`** (0 high/critical):
   - medium ×3, one issue: a pre-existing regular `~/.config/tmux/local.conf` blocks the boot-off link. hal has no tmux config today.
   - low: no brew cache in `macos-server`; doctor flags a desk machine-local `local.conf` (`if:` not honored); no seeded `local.conf` case in CI; `install_tmux.sh` cleanup status ignored; brew prefix comes from `uname -m`, not `brew --prefix`.
   - Earlier medium, unfixed: an old `~/.config/nvim` link left by a previous desk install stays active on server.
3. **review-stack can't complete on this PR.** Every head gets verdict `partial` (policy-excluded-path), because it doesn't review the four `*.server` files. Atlas or David must decide whether a partial counts, or extend the reviewer's file-type policy.
4. **Before the first real run on hal (Atlas):**
   - Grep `dev.hal.*` LaunchAgents and `~/bin` scripts for zsh, because zshenv now puts GNU coreutils first for every zsh.
   - Move aside any regular `~/.gitconfig`.
   - Full list in the PR body.
5. This HANDOFF.md is **not committed**: committing it on `feat/server-layer` would change #203's head and trigger another review run. Commit it on master after the merge if wanted.

## Gotchas & Watch-outs
- This VPS session runs **inside tmux**, so `$TMUX` is set. Any local tmux experiment must `env -u TMUX` and use a scratch `TMUX_TMPDIR`, or it talks to the live server.
- The worktree has a repo-local git identity (`git config user.*`), because this host has none globally. There's no pre-commit hook here, so gitleaks was run by hand.
- Desk parity check: dry-run master vs branch with a scratch HOME. Darwin is simulated through a `uname` shim, which works because `--dry-run` runs no helpers. Desk output was identical after every fix round.
- The real macOS dry-runs and installs only happen in CI (`macos`, `macos-server`).
