# HANDOFF — 2026-07-14, evening (PST)

Full-repo **10x audit session** (Fable 5, max effort). Produced an evidence-backed strategy
brief (~45 findings, all with file:line evidence), verified upstream facts live, benchmarked
the shell, ran secret scans, and converted everything into a PR-sized execution plan:
**`docs/plans/2026-07-14-001-chore-10x-roadmap-execution-plan.md`** — the authoritative
artifact for the overnight execution loop (Opus 4.8 + Codex adversarial review). Baseline:
`master @ 2950864`, tree clean, CI green, no open PRs/issues.

## Headline findings (full detail + evidence lives in the plan doc)

- **BOOT-01 (critical):** `helpers/install_omz.sh` uses a bash-4 associative array; under
  macOS `/bin/bash` 3.2 the plugin map is empty → fresh Macs/CI silently install **0/4 OMZ
  plugins** while reporting success. The prior handoff's "arithmetic warning" item
  underdiagnosed this. Reproduced live.
- **SEC-01 (high):** iTerm2 actively **live-syncs prefs into the repo** (`PrefsCustomFolder`
  = repo `iterm/`, `LoadPrefsFromCustomFolder` = 1, verified via `defaults read`) — the tracked
  plist carries two usernames, a corporate hostname, command history, and an 838-line window-
  arrangement blob. CI's PII grep never covered `iterm/`.
- **HYG-01 (high):** `fonts/` = 189 MB (96 files; `Fura Code` is a pre-2019 duplicate of Fira
  Code); everything-else-tracked = 1.0 MB. All needed families exist as homebrew casks
  (verified live 2026-07-14).
- **BOOT-02/NVIM (high):** `nvim/custom` targets removed NvChad v1.0 APIs while
  `install_nvim.sh` clones unpinned HEAD (v2.x, `custom/` mechanism deleted upstream);
  live `~/.config/nvim` is a non-git 2022 fossil. Fresh machine = broken editor.
- **CI-01 (REVERSED 2026-07-14):** the `HOMEBREW_BUNDLE_JOBS: '1'` pin is NOT droppable. The
  upstream #22297 fix shipped in Homebrew 5.1.12 and reached the runner (6.0.5+), but run
  `29301199411` (image `20260706.0213.1`, Homebrew ≥6.0.5) still hit the Cellar-lock race — so
  #22297 doesn't cover this Brewfile's contention. Keep the pin (P0-4 repurposed to a comment/doc
  correction). Current Homebrew defaults bundle jobs to parallel `auto`, so real machines are
  exposed too.
- **BOOT-05:** Brewfile is a stale dump — 99 installed-but-unrecorded, 7 recorded-but-missing,
  ~30 transitive deps as fake intent; `export_deps` regeneration would corrupt scoped npm names.
- **TMUX-01:** `tmux-attention.sh` spinner cleanup `pkill` prefix-collides (pane `%2` kills
  `%20`'s loop).
- Startup is **healthy**: 240 ms median / 350 ms cold (12 samples) — speed is not the story;
  correctness/hygiene/feedback-loops are.

## Obscura adversarial-review protocol (verified this session)

- Project = `~/Projects/browse-gateway` (CLI brand **Obscura**, `src/cli/obscura.ts`).
- Its SOP (`codex-review-loop-sop`, HANDOFF there): each change lands only after a Claude↔Codex
  **adversarial-review loop returns `approve`**; verify-don't-blind-accept each finding;
  commit each fix round; up to ~10 rounds.
- Mechanism: `codex@openai-codex` plugin v1.0.6 (already enabled in `claude/settings.json`,
  PR #95) → `/codex:adversarial-review` → `codex-companion.mjs` → Codex CLI 0.144.1 with
  `~/.codex/config.toml`: **`model = "gpt-5.6-sol"`, reasoning `high`**. Verdicts: `approve` /
  `needs-attention` (structured JSON, file+lines+confidence).
- **Gotcha (from Obscura):** run `--wait` inside a *detached background task*; plain
  `--background` is killed by the 2-min shell timeout mid-handshake, leaving an orphaned
  "running" job. Verify pid + log mtime, not the status field.

## What's Next

1. **Execute the roadmap**: new session (Opus 4.8, high effort), paste the mission prompt
   (operator has it on the clipboard; identical protocol is §Loop-protocol of the plan doc).
   19 packets, strict order P0-1 → P3-1, one branch/PR/squash-merge per packet, Codex
   adversarial review gate (≤10 rounds) before every commit, master stays green.
2. Morning: work the **manual checklist** in the plan doc (iTerm prefs flip, font visual check,
   brew reconcile, mcpconfig relocation, parked PRs).
3. External items carried from 2026-07-07 (unchanged): Foreman naming, domain buys, Ship Sigma
   calculator, Dec 11 redirect-flip calendar event.

## Gotchas & Watch-outs

- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (see #97→#99 lesson).
- **No machine-side uninstalls overnight** — repo-side changes only; machine reconciliation is
  a morning-checklist activity (plan doc §Safety-rails).
- **iTerm defaults flip is manual** — iTerm rewrites the prefs folder on quit; don't fight it
  from a background agent.
- **`claude/settings.json` is now the shared cross-machine baseline** (P2-7 landed, D5): the
  `model`/`effortLevel` pins, the two dead marketplaces (`claude-code-plugins`,
  `villavicencio-skills-private`), and the host-specific `curl`/`ssh root@openclaw-prod`
  auto-allow rules were removed. Claude Code has **no user-level `*.local` override layer**
  (`settings.local.json` is project-scoped only), so genuinely per-machine user settings must
  live on that machine's own `~/.claude/settings.json`, not be committed here.
- **The P2-7 change is currently INERT on the personal Mac** and applying it is a manual step.
  The live `~/.claude/settings.json` is a **regular file** (decoupled from the repo — it still
  carries the old pins + `curl`/`ssh` allow rules). Dotbot's `link` defaults are `relink: true`
  with **no `force`**, so `./install` will *not* overwrite a regular file — it reports a link
  failure and leaves the old settings active. To actually apply the hygiene change on a machine
  (morning-checklist, **do not auto-delete — it's live user data**): (1) back up the live file
  (`cp ~/.claude/settings.json ~/.claude/settings.json.bak`); (2) remove it; (3) run `./install`
  so Dotbot creates the symlink; (4) verify `~/.claude/settings.json` is now the symlink and the
  removed rules are absent (`readlink ~/.claude/settings.json`; `jq '.model // "gone"'`). A fresh
  session will then see more permission prompts — by design.
