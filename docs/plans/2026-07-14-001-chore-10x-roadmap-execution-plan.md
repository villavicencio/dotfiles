# Plan: Dotfiles 10x Roadmap — Overnight Execution Loop

---
title: Dotfiles 10x roadmap — packet-by-packet execution with Codex adversarial review
date: 2026-07-14
status: active
module: repo-wide
tags: [audit, roadmap, adversarial-review, codex, loop]
problem_type: maintainability_debt
---

## Context

A full-repo audit (Fable 5, 2026-07-14, session on `master @ 2950864`) produced a strategy
brief with ~45 evidenced findings and a PR-sized roadmap. This plan is the execution contract
for an autonomous session (Opus 4.8) that resolves the roadmap packet-by-packet overnight.

**Protocol origin:** mirrors the browse-gateway (Obscura) `codex-review-loop-sop` — each change
lands only after an autonomous Claude↔Codex adversarial-review loop returns `approve`
(Codex CLI 0.144.1, model `gpt-5.6-sol`, reasoning `high` per `~/.codex/config.toml`; the
`codex@openai-codex` Claude plugin v1.0.6 is already enabled in `claude/settings.json`).

## Loop protocol (per packet)

1. `git checkout master && git pull` — start clean; verify `git status --short` is empty.
2. Create the packet branch (names below).
3. Implement exactly the packet scope. Static checks: `zsh -n` / `bash -n` / `shellcheck -S warning`
   on touched scripts; `./install --dry-run` must stay mutation-free when Dotbot YAML changes.
4. Run the packet's **acceptance commands** (below). All must pass before review.
5. **Adversarial review loop** (max 10 rounds):
   - Invoke `/codex:adversarial-review --wait <packet focus text>` **inside a detached
     background task** (`run_in_background: true`), then poll `/codex:status`; fetch with
     `/codex:result`. Never use plain `--background` — the 2-min shell timeout kills the
     handshake and leaves an orphaned "running" job (browse-gateway HANDOFF, verified gotcha).
     Verify liveness by pid + log mtime, not the status field alone.
   - Verdict contract: structured JSON; `approve` = ship; `needs-attention` = blocking findings
     (file, line range, confidence, recommendation).
   - **Verify-don't-blind-accept:** reproduce/confirm each finding before fixing — in the
     browse-gateway run several Codex findings were wrong, and several "Low" ones were real.
     Fix confirmed findings, rebut false ones in the next round's focus text.
   - Re-run until `approve`. If round 10 ends without `approve`: push branch, open **draft PR**
     with a state summary, log it as PARKED, move to the next packet.
6. Commit with a conventional message (`fix:`/`feat:`/`chore:`/`docs:`/`ci:` + body: what/why,
   findings addressed, review rounds count). One packet = one logical commit (fixup commits
   from review rounds are fine; squash-merge collapses them).
7. Push, `gh pr create` (body: scope, finding IDs, acceptance evidence, review rounds),
   `gh pr checks --watch` until green (macOS leg ≈ 9 min), then
   `gh pr merge --squash --delete-branch`. Master must stay green — never merge red.
8. Append one line to the run log (`docs/plans/2026-07-14-001-run-log.md`, create on first
   packet): packet, PR#, merge SHA, review rounds, notes.
9. Next packet.

While waiting on CI you may prepare the next packet's branch in parallel (worktree or stash),
but merge strictly in order.

## Safety rails (hard rules)

- **Never touch the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (see HANDOFF gotcha, PR #97→#99).
- **No git history rewrite, no force-push** (Decision D2 = keep history; fonts deleted from tip only).
- **No machine-side uninstalls or bulk installs overnight.** Repo files change; the live machine
  is only touched by: installing the two font casks (additive, needed for verification) and
  running read-only checks. `brew bundle cleanup`, removing old fonts from `~/Library/Fonts`,
  uninstalling the `claude-code` cask → morning checklist.
- **Do not delete or move untracked local files** (`install.conf.yaml.bak`, `mcpconfig.json`,
  `.idea/`, `install_tmux.log`) — morning checklist items; data-safety rule applies.
- **iTerm2:** repo-side work only (P1-1). Do NOT run `defaults write com.googlecode.iterm2 …`
  overnight — iTerm may be running and will fight/overwrite. Manual flip is on the checklist.
- **P2-7 (claude settings) runs LAST** among Phase-2 packets — it narrows the very allow-rules
  the running session may depend on.
- Secrets: never print values; gitleaks pre-commit stays active; if it blocks a commit,
  investigate — do not `--no-verify`.
- If a packet's acceptance can't be met without expanding scope, PARK it (draft PR + log) rather
  than improvising.

## Decision defaults (owner-endorsed 2026-07-14; apply without re-asking)

- **D1 Neovim:** self-contained lazy.nvim config in-repo replacing the NvChad overlay (P3-1).
- **D2 Fonts history:** no rewrite; delete from tip only.
- **D3 License:** add MIT `LICENSE` (README already claims it).
- **D4 Vale:** slim-and-wire — root `.vale.ini` pointing at `vale/`, prune GitLab style to a
  small useful rule set (~6), run in `dot check`; do not delete the directory.
- **D5 Claude settings:** remove tracked `model`/`effortLevel` pins and the two `curl` +
  `ssh root@openclaw-prod` auto-allow rules; personal-risk rules move to `settings.local.json`.
- **D6 PII policy:** `/Users/dvillavicencio` acceptable inside `docs/**` narrative; blocked
  everywhere else (CI grep allowlists docs/).
- **D7 Ruby:** keep RVM (live at `~/.rvm`); drop `rbenv` + brew `ruby` from Brewfile.

## Packet queue (execute in this order)

Every packet: branch name, scope, key evidence (no rediscovery needed), acceptance.

### 1. P0-1 `fix/omz-install-bash32`
Scope: `helpers/install_omz.sh`. Replace the bash-4 associative array (lines 21-26) with a
bash-3.2-safe structure (e.g. `plugin|url` string list); add `set -euo pipefail`; pin the OMZ
installer (line 14: unpinned `curl … raw.github.com … master | sh`) to a tag/commit and set
`RUNZSH=no CHSH=no KEEP_ZSHRC=yes`.
Evidence: `/bin/bash 3.2.57 -c 'declare -A P=(["zsh-256color"]="x")'` → `value too great for
base`; loop then iterates nothing; script still prints success ⇒ fresh Macs/CI install **0/4**
OMZ plugins silently. HANDOFF's "arithmetic warning" framing underdiagnosed this.
Acceptance: `HOME=$(mktemp -d) /bin/bash helpers/install_omz.sh` → exits 0 AND 4 plugin dirs
exist under `$HOME/.oh-my-zsh/custom/plugins/`; CI green.

### 2. P0-2 `ci/outcome-assertions`
Scope: `.github/actions/install-matrix-post-apply/action.yml`. Add: (a) assert each of the 4 OMZ
plugin dirs exists; (b) `zsh -i -c true` **stderr must be empty** (catches "plugin not found",
bash arithmetic noise); (c) assert TPM + plugins dir non-empty; (d) startup budget: 10×
`zsh -i -c true`, fail if median > 800 ms (runner-generous).
Evidence: R4 today is exit-code-only (`action.yml:38-47`) — BOOT-01 shipped green for months.
Acceptance: seeded-fault branch (temporarily misspell a plugin name) fails CI; master green.

### 3. P0-3 `fix/tmux-attention-pkill-anchor`
Scope: `claude/hooks/tmux-attention.sh:47-54`. `pane_safe` strips `%` from `$TMUX_PANE`, so
`pkill -f "claude-spinner-marker-2"` also matches `-20`, `-21`, `-200`. Anchor the marker (add a
terminal delimiter, e.g. `…-marker-${pane_safe}-x`) so prefix collisions are impossible while
`pkill -f claude-spinner-marker` (manual sweep, documented in CLAUDE.md) still matches.
Acceptance: with two panes whose ids are prefix-related (spawn stub loops), clearing one leaves
the other's loop alive; `zsh -n`/`bash -n` clean; hook still sets/clears `@claude_status`.

### 4. P0-4 `ci/drop-brew-bundle-jobs-pin`
Scope: `.github/workflows/install-matrix.yml:145-162`. Delete `HOMEBREW_BUNDLE_JOBS: '1'`; fix
the comment (#22293 is the issue, #22297 the fix PR).
Evidence: fix merged 2026-05-16 → Homebrew 5.1.12; macos-15 image `20260629.0276.1` ships 6.0.5.
Acceptance: macOS leg green with zero `already locked` lines (check run log); record wall-clock
delta in run log. Rollback: re-add the env line.

### 5. P0-5 `fix/remove-orphan-rigellute-tap`
Scope: `brew/Brewfile:1`. Nothing is installed from `rigellute/tap` (verified); same dead-tap
failure class as adoptopenjdk (#96).
Acceptance: CI green; `brew bundle check --file=brew/Brewfile` output unchanged vs master.

### 6. P1-4 `chore/delete-tracked-debris`
Scope: `git rm` `logs/all.log logs/error.log` (empty, Apr 2025) + the six
`claude/commands/*.md.deprecated` (all superseded 1:1 by `dv` plugin skills — verified); add
`logs/` to `.gitignore`; drop the `~/.claude/commands` create at `install.conf.yaml:79` (keep
`~/.claude/skills` — 17 live entries).
Acceptance: `git ls-files | grep -E '\.deprecated|^logs/'` empty; `/pickup`-class dv skills
still listed; CI green.

### 7. P1-3 `chore/brewfile-curation`
Scope: `brew/Brewfile` hand-curated into commented intent sections (~55 entries): drop the
transitive-dep attic (`bdw-gc berkeley-db boost brotli c-ares cffi docbook docbook-xsl freetype
gdbm gdk-pixbuf giflib guile imlib2 libpthread-stubs libtermkey libuv libvterm libxml2 libxslt
libzip luv msgpack pcre portaudio xmlto util-linux gnu-getopt` and similar), drop `node` (nvm
owns node), drop `rbenv` + `ruby` (D7), drop `python@3.10` (pyenv owns Python), review oddballs
(`handbrake irssi jrnl screenfetch the_silver_searcher most mac-cleanup-py kondo grc icdiff
source-highlight cpanminus ack`) — keep only what's wanted, comment why. Add `zsh-completions`
fpath decision (wire or drop, ZSH-12). Rewrite `export_deps` → `helpers/report_drift.sh`
(read-only: `brew bundle check` + `brew bundle cleanup` dry list + npm globals diff; never
overwrites manifests — the old `ls $(npm root -g)` breaks scoped packages).
Evidence: 99 installed-but-unrecorded, 7 recorded-but-missing, measured 2026-07-14.
Acceptance: CI macOS leg green (and faster — log delta); `helpers/report_drift.sh` runs
read-only; Brewfile entries each carry a section/comment. Machine reconciliation → checklist.

### 8. P1-1 `feat/iterm-dynamic-profile` (repo side only)
Scope: author `iterm/profile-dynamic.json` (iTerm2 Dynamic Profile) carrying the intentional
prefs from the current plist — fonts (`JetBrainsMonoNF-Regular 13`, non-ASCII
`FiraCodeNerdFontComplete-Light 14` — update names if P1-2 lands first), ANSI colors,
`GlobalKeyMap` incl. Shift+Enter mapping, pointer actions; Dotbot-link it into
`~/Library/Application Support/iTerm2/DynamicProfiles/`. `git rm`
`iterm/com.googlecode.iterm2.plist` + `iterm/profile.json`. Widen the CI PII grep
(`install-matrix-post-apply/action.yml:20,32-33`) to all tracked files minus `docs/**` (D6),
adding patterns for `/Users/david\b` and hostnames. Write the manual-flip runbook into the PR
body + morning checklist.
Evidence: live sync confirmed (`PrefsCustomFolder` = repo `iterm/`, `LoadPrefsFromCustomFolder`
= 1); plist holds two usernames, `zs-MacBook-Pro.local`, command history, an 838-line window
arrangement blob (lines ~2843-3680).
Acceptance: `git grep -E 'zs-MacBook|/Users/david\b'` empty; seeded `/Users/test/` in a
non-docs file fails the widened CI grep; dynamic-profile JSON validates (`plutil -lint` for
plist-JSON or `jq .`); CI green. Manual: prefs-folder flip + keymap verification (checklist).

### 9. P1-2 `feat/fonts-via-casks`
Scope: add `cask "font-jetbrains-mono-nerd-font"` + `cask "font-fira-code-nerd-font"` (both
verified in homebrew/cask @ Nerd Fonts 3.4.0) to Brewfile; delete `fonts/` (96 files, 189 MB —
`Fura Code` is a pre-2019 duplicate of Fira Code), `helpers/install_fonts.sh`, the
`install.conf.yaml:22` `~/.local/share/fonts` create and `:72` helper call; fix
`starship/starship.toml:81` deprecated swift PUA glyph; update font names referenced by the
P1-1 dynamic profile (post-3.0 PostScript names differ, e.g. `JetBrainsMonoNF-Regular` →
verify with `system_profiler SPFontsDataType | grep -i jetbrains` after cask install).
Overnight-allowed machine change: `brew install --cask` the two fonts (additive) to verify.
Acceptance: `./install --dry-run` clean on fresh `$HOME`; repo `du -sh` ≤ 15 MB
(tracked-sans-fonts is 1.0 MB); tmux pills + glyphs render (visual check next morning noted);
CI green.

### 10. P2-6 `docs/truth-pass`
Scope: rewrite `README.md` honestly (~80 lines: what/why, two-Mac model, `./install
[--dry-run]`, structure table, machine overrides, CI badge; kill `yourusername` placeholder);
add MIT `LICENSE` (D3); fix `CLAUDE.md:32` (osx/), `:43-44` (commands), `:163-174`
(tmux-window-namer now in `dv` plugin; repo keeps the tmux-side infra); add
`docs/solutions/INDEX.md` generator (`helpers/generate_docs_index.sh` or inside `dot`) grouping
by module/severity with an "archived/superseded" section; normalize solution frontmatter (7
missing `module`, 6 missing `problem_type`, unify `severity` casing, fix
`printf-hex-escape…md` path-as-category); flip stale plan statuses (`2026-04-14` VPS plan →
`abandoned`, `2026-05-01` location pill + `2026-05-03` CI matrix → `completed`, `2026-05-27`
browse-gateway → `externalized`, `2026-04-17` glyph seed → `superseded`); append the 2026-04-14
`handoff.md:147` history finding (OpenClaw internal bearer, host destroyed 2026-05-20, risk
nil) to `docs/solutions/security/2018-…md` as an addendum.
Acceptance: every README command copy-pastes on a fresh clone; INDEX regenerates
deterministically (run twice → no diff); `git grep -c yourusername` = 0; CI green (md-only
changes skip the matrix — that's fine).

### 11. P2-3 `fix/zsh-dead-config-sweep`
Scope (all verified findings): `zsh/zshenv` — replace lines 46-47 `DOTFILES=$(git …)` with a
subprocess-free derivation (`DOTFILES=${${:-$ZDOTDIR/.zshrc}:A:h:h}`), delete `NVM_LAZY`/
`NVM_COMPLETION` (129-132), `MYVIMRC` (181), `LUA_PATH` (195), `HOMEBREW_INSTALL_CLEANUP`
(122), fix the "32³" comment (113); keep a single `NVM_DIR` (drop the duplicate at
`zshrc:111`). `zsh/zshrc` — replace the dead fzf block (81-96; `~/.fzf.zsh` doesn't exist and
the shims were never `zle -N` widgets) with `command -v fzf >/dev/null && source <(fzf --zsh)`
plus the existing atuin `^R` restore lines; move the two completion zstyles (8-9) below the OMZ
source or hardcode a cache dir; swap plugin order so `zsh-history-substring-search` loads AFTER
`zsh-syntax-highlighting` (fix comment); drop `zsh-256color` from `plugins=(…)` AND from
`helpers/install_omz.sh` (obsolete; also the BOOT-01 trigger string); `sleep 1s` → `sleep 1`
(182); gate `zsh/iterm2.zsh:148` aliases on `[[ $TERM_PROGRAM == iTerm.app ]]` or dir existence.
Acceptance: `zsh -n` all files; `env TERM_PROGRAM=x TMUX= zsh -i -c true` stderr-empty; `zsh -c
'echo $DOTFILES'` correct; `bindkey '^T'` shows fzf widget when fzf present; startup median ≤
baseline 240 ms (run 10×); CI green.

### 12. P2-4 `chore/legacy-alias-curation`
Scope: `zsh/alias.sh` — fix `lsd` (21, lost its dir filter), delete broken/dangerous legacy
(`sniff`/`httpdump` en1+ngrep 68-69, `emptytrash` 88, `lscleanup` 64, `chromekill`, `afk`,
`badge`, `map`, `spotoff/spoton`, opendns `ip`/`ips` 56-58 — keep `localip`), delete obsolete
`tmux -f` alias (129; tmux ≥3.2 reads XDG natively, machine runs next-3.8). `zsh/functions.sh`
— delete `json()` (pygmentize; `jq` already colorizes), `escape`/`unidecode`/`codepoint`
(perl one-offs), keep `digga`/`tre` (tree installed); unset the loop var (53).
`git/gitconfig` — delete dead `push = push -u` alias (57; git ignores builtin-shadowing
aliases) and gitflow blocks (23-31); drop `diff "exif"` textconv (32-33) + `git/gitattributes`
exif lines (exiftool not installed); replace hardcoded `/opt/homebrew/bin/gh` (81,84) with bare
`gh`. List every deletion in the PR body for veto.
Acceptance: every surviving alias/function's binary exists (scripted `command -v` sweep);
`git config --get-regexp alias` clean; `git diff` on an image no longer errors; CI green.

### 13. P2-8 `fix/tmux-polish`
Scope: `tmux/tmux.display.conf` — `status-interval 5` + fix stale comment (22-23); verify
spinner still animates (hook writes user options → immediate redraw; if not, use 2). Delete the
`C-l` identity bind (26). `tmux/tmux.general.conf` — guard the save-on-attach hook (85) so an
empty/fresh server doesn't clobber a good resurrect snapshot (e.g. only save when
`#{session_windows}` > 1 or a restore-completed marker exists); delete tmux<2.2 UTF-8 lines
(33-34). `tmux/tmux.conf` — replace `$DOTFILES` sources (1-2) with `$XDG_CONFIG_HOME`-anchored
or absolute Dotbot-managed paths so a server started without shell env still loads. Empty the
stale OpenClaw seed in `tmux/window-meta.linux.json` to `{}` (keep mechanism + comment).
Acceptance: `tmux -f ~/.config/tmux/tmux.conf` inside `env -i HOME=$HOME
XDG_CONFIG_HOME=$HOME/.config` starts clean (kill test server after); spinner animation
verified; reboot-restore note added to checklist; CI green.

### 14. P2-5 `ci/weekly-schedule`
Scope: `install-matrix.yml` — add `schedule: [cron: '0 14 * * 1']` (Mon 6/7am PT) +
`workflow_dispatch` stays; add a failure step that opens/updates a pinned issue
(`gh issue create/comment`) so scheduled reds are seen (needs `issues: write` — scope the
permission bump to a separate job with least privilege, keep the matrix jobs at
`contents: read`).
Acceptance: `workflow_dispatch` run green; YAML lints (`gh workflow view`); permissions diff
reviewed in PR body.

### 15. P2-2 `refactor/dotbot-layered-configs`
Scope: split `install.conf.yaml`/`install-linux.conf.yaml` into `dotbot-conf/base.yaml` +
`darwin.yaml` + `linux.yaml`; `install` wrapper runs dotbot once per layer (base then
platform). Delete: dead non-Darwin locale block (macOS yaml 28-33), no-op `. ~/.zshenv` items,
duplicated link blocks. Guard `chsh` on `[ "$SHELL" != "$(command -v zsh)" ]` and delete the
contradictory completion message (93-98). Add the standard `DOTFILES_DRY_RUN` guard block to
`install_packages.sh` (macOS branch), `install_brew.sh`, `install_from_brewfile.sh`,
`install_nvm.sh` (+ quote its SC2046 substitutions, drop the duplicate `. nvm.sh`); make
`install_tmux.sh` log to `${XDG_CACHE_HOME:-$HOME/.cache}` instead of repo root.
Acceptance: `./install --dry-run` output is functionally identical (same Would-create set) on
both platforms — compare sorted link lines pre/post; CI R2+R3 green on both legs; direct
`DOTFILES_DRY_RUN=1 bash helpers/<each>.sh` previews without mutating.

### 16. P2-1 `feat/dot-cli`
Scope: new `bin/dot` bash dispatcher (no new deps) with subcommands: `install` (wrapper
passthrough), `doctor` (read-only: symlink targets resolve, 4 OMZ plugin dirs, TPM present,
orphan taps vs Brewfile, `brew bundle check` summary, `report_drift.sh`, broken-alias
`command -v` sweep, `gitleaks dir` repo-folder scan, HANDOFF.md age > 7d warn, docs INDEX
freshness, nvm version sprawl, `which -a` shadow report for node/ruby/python/claude), `check`
(shellcheck + `zsh -n`/`bash -n` + dotbot dry-run parse — local mirror of CI), `bench` (10×
interactive startup, prints median/max vs 300 ms budget), `drift` (alias for report_drift),
`update` (topgrade), `explain <name>` (locate + print alias/function/bind definition),
`docs-index` (regenerate INDEX.md). Symlink into `~/.local/bin/dot` via Dotbot. README section.
Acceptance: `dot doctor` < 10 s, exits non-zero when a fault is seeded (break a symlink in a
temp HOME test), zero mutations (verify with before/after `find` snapshot à la CI R2);
`dot bench` prints distribution; `dot check` matches CI static results; CI green.

### 17. P3-2 `feat/agents-md`
Scope: new `AGENTS.md` — canonical tool-neutral repo brief distilled from CLAUDE.md (structure,
conventions: `$HOME`/`$BREW_PREFIX`/no-hardcoded-paths, branch/PR workflow, dry-run contract,
verification commands incl. `dot check`, invariants: Otty block, lazy-loader pattern, tool-
managed blocks); slim repo `CLAUDE.md` to Claude-specific behavior + a pointer/import of
AGENTS.md content (keep CLAUDE.md self-sufficient for Claude Code loading — duplication is
acceptable only for the ~10-line header table); `dot doctor` check that both files' referenced
paths exist.
Acceptance: a fresh Codex session (`codex exec` with a "how do I add a brew package and verify"
prompt, read-only sandbox) answers correctly from AGENTS.md alone; CI green.

### 18. P2-7 `chore/claude-settings-hygiene` (run LAST before P3-1)
Scope (D5): `claude/settings.json` — remove `Bash(curl -fsSL*)`, `Bash(curl -s*)`,
`Bash(ssh root@openclaw-prod*)` allow rules (157-161), remove `model` (5) + `effortLevel`
(131) pins, remove the two dead marketplaces `claude-code-plugins` (93-98) and
`villavicencio-skills-private` (118-123); document in-file (comment key or README note) that
machine/session-specific bits belong in `settings.local.json`. Update the HANDOFF gotcha about
settings churn.
Acceptance: `claude` plugins still load (dv + codex list in a fresh `claude --help`-level
check or next session); JSON validates (`jq .`); gitleaks hook passes; CI green.
NOTE: after this merges, the running session may see more permission prompts — that is
expected and why this packet is sequenced last.

### 19. P3-1 `feat/nvim-self-contained` (attempt only if all above are merged; park-friendly)
Scope (D1): replace `nvim/custom` overlay with a complete `nvim/` config (becomes
`~/.config/nvim` via Dotbot): lazy.nvim bootstrap pinned + committed `lazy-lock.json`;
port the used plugin set — which-key, cutlass, neoscroll, vimwiki + markdown stack (mkdx or
modern equivalent, table-mode, pencil), conform.nvim (replaces archived null-ls; stylua/shfmt
via Mason), nvim-lspconfig (`lua_ls`, `ts_ls`, `bashls`, `vimls`) + Mason for servers,
treesitter, One-Dark theme matching tmux/iTerm palette (#ABB2BF/#7DACD3 family), keep the
Obsidian vimwiki path behind a `vim.fn.isdirectory` guard. Rewrite `helpers/install_nvim.sh`:
no NvChad clone, just ensure config link (Dotbot owns it) + `nvim --headless "+Lazy! restore"
+qa` bootstrap. Update `install.conf.yaml` link (whole-dir `~/.config/nvim` instead of
`lua/custom`). MUST preserve rollback: move existing `~/.config/nvim` to
`~/.config/nvim.nvchad-backup-2026-07-14` (do NOT delete), same for
`~/.local/share/nvim` → fresh data dir.
Evidence: overlay targets removed NvChad v1.0 APIs (six broken `require("nvim.custom.*")`,
`nvchad.map` nil on v2); live `~/.config/nvim` is a non-git 2022 fossil; installer clones
incompatible HEAD.
Acceptance: `HOME=$(mktemp -d)`-style test: config links, `nvim --headless "+Lazy! sync" +qa`
exits 0; on the real machine: backup exists, `nvim +checkhealth` has no errors in lsp/lazy
sections, `:e some.sh` attaches bashls; lockfile committed; CI green (add the headless boot
check to post-apply if stable). Review focus: data-loss paths (backup!), portability, pin
integrity.

## Manual morning checklist (agent: keep this list updated in the run log)

1. iTerm2: quit iTerm → `defaults write com.googlecode.iterm2 PrefsCustomFolder -string
   "$HOME/.config/iterm2"` (or disable custom folder) → relaunch → confirm Dynamic Profile
   applied; verify Shift+Enter mapping + fonts; delete stray old plist copies from the repo dir
   if iTerm re-wrote any (keep repo clean).
2. Fonts: visually confirm tmux pill glyphs + starship symbols; then optionally remove the ~149
   old copied fonts from `~/Library/Fonts` (cask-managed copies remain).
3. Machine⇄Brewfile reconcile: review `helpers/report_drift.sh` output; run `brew bundle
   install` for wanted missing items; decide the 99 unrecorded (incl. `claude-code` cask —
   native `~/.local/bin/claude` wins PATH; uninstalling the cask is safe after confirming
   `~/.local/bin/claude --version` works).
4. `mcpconfig.json` (contains a live JWT): move to `~/.config/<consumer>/` once its consumer is
   identified; it is gitignored but shouldn't live in a public repo's folder.
5. Delete local `install.conf.yaml.bak` (stale pre-#57 pipeline copy) if no longer wanted.
6. Review any PARKED draft PRs.
7. D5 confirmation: new sessions now start unpinned (model/effort) — set per-session as desired.

## End-of-run deliverables (mandatory)

1. `docs/plans/2026-07-14-001-run-log.md` — one row per packet: PR#, SHA, rounds, result
   (MERGED/PARKED/SKIPPED), notes; plus metrics: repo `du -sh` before/after, macOS CI wall-clock
   before/after, startup median before/after, packets merged count.
2. Rewrite `HANDOFF.md` (dv:handoff style): summary, decisions, what didn't work, next steps
   (= remaining packets + morning checklist), gotchas.
3. Commit both as `docs:` (direct to master is fine for docs).
4. Leave `master` green, working tree clean, no branches checked out.
