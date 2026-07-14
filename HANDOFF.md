# HANDOFF — 2026-07-13, evening (PST)

Started with `/pickup` and found the prior handoff (2026-07-07) had drifted: back on `master`
with a new dirty file, and the "next up" item (merge PR #95) was blocked by a **red macOS CI**.
The session became a full CI-rot investigation + cleanup — diagnosed two distinct macOS-CI
failures, fixed both, handled a terminal installer's shell block (twice — conformed in #97, then
reverted in #99 when the tool fought back), cleared the queue via a coordinated merge, and
compounded two solution docs. **Master is green and the queue is empty.**

## What We Built

Five PRs **MERGED** (squash, branches deleted) + two solution docs. Master head: `16285f4`.

- **PR #96 (MERGED, `f94ab5a`)** — `fix: remove dead adoptopenjdk/openjdk tap from Brewfile`.
  Root cause: modern Homebrew audits a tap's cask definitions on `brew tap`, and
  `adoptopenjdk-jre` still uses the removed `appcast` stanza → `undefined method 'appcast'` →
  "Tapping adoptopenjdk/openjdk has failed!" → `brew bundle` fails. The `tap "adoptopenjdk/openjdk"`
  line in `brew/Brewfile:1` was **orphaned** — no cask installed from it, it was the sole
  adoptopenjdk reference in the repo, present since the original Dotbot conversion. Removal is
  behavior-preserving (no Java was being installed). Want a JDK later → add `cask "temurin"`.

- **PR #98 (MERGED, `ab3c347`)** — `fix: force serial brew bundle in CI to stop Cellar lock-race`.
  Added `HOMEBREW_BUNDLE_JOBS: '1'` to the macOS job `env:` in
  `.github/workflows/install-matrix.yml`. Root cause: an "already locked …/Cellar/<keg>" error
  requires two concurrent `brew` processes, so `brew bundle` was installing in **parallel** on the
  runner even though our helper passes no `--jobs` and Homebrew's upstream default is `--jobs=1` —
  the `macos-15` runner image injects a higher bundle job count. Parallel installs race on
  shared-dependency Cellar locks (`go` pulled by `gitleaks`; `luajit` by `luarocks`). Serial
  install kills it. **Verified:** #98's macOS log had ZERO `already locked` lines (failure count
  dropped 3 → 1, that 1 being adoptopenjdk which #96 removed).

- **PR #97 (MERGED, `e36f26b`)** — `chore: conform Otty shell-integration block to repo idiom`.
  The Otty terminal installer appended a multi-line POSIX block to `zsh/zshrc` (`if [ -n … ]`,
  `.` sourcing, `# >>>`/`# <<<` markers). Rewrote it as a single guarded one-liner matching the
  gcloud/openclaw/antigravity idiom directly above it:
  `[[ -n "$OTTY_SHELL_INTEGRATION" && -r "$OTTY_SHELL_INTEGRATION/otty-integration.zsh" ]] && source …`.
  **Verified:** `zsh -n` parses + sources cleanly under Otty. **⚠️ Reversed by #99 (below)** — Otty
  re-added its markered block within the session; conforming fought the tool.

- **PR #95 (MERGED, `8ca976f`)** — `chore: register openai-codex plugin in Claude settings`.
  Carried over from the 2026-07-07 session (was OPEN at pickup). Rebased onto the fixed master
  and merged. Net diff is only the `codex@openai-codex` plugin + `openai-codex` marketplace
  addition in `claude/settings.json`.

- **PR #99 (MERGED, `16285f4`)** — `fix: let Otty manage its own shell-integration block`.
  Reverts #97. Otty uses its `# >>>`/`# <<<` markers to detect whether its integration is
  installed; #97 removed them, so Otty re-appended a fresh block on shell launch — a duplicate in
  the Dotbot-symlinked live `zshrc`, verified within one session of #97 merging. Restored Otty's
  block **verbatim** so it matches its own markers and stops re-adding. CI green (linux + macOS).

- **Two `docs/solutions/` entries (`30e48aa`)** — compounded the CI-rot fixes under
  `docs/solutions/cross-machine/`: `adoptopenjdk-dead-tap-fails-brew-bundle-2026-07-13.md` and
  `brew-bundle-parallel-cellar-lock-race-macos-runner-2026-07-13.md`, cross-linked to each other
  and the existing install-matrix docs.

## Decisions Made

- **Two CI bugs = two PRs.** adoptopenjdk removal (#96) and the lock-race fix (#98) are distinct
  logical changes, kept separate per repo convention even though each branch alone still showed
  the *other's* failure (mutually blocking for a green check).
- **Otty block → let the tool own it (verbatim markered block).** Initially conformed to the repo
  one-liner idiom (#97), but Otty re-added its markered block within the session — it self-manages
  via its `# >>>` markers. Final call (#99, operator chose via prompt): keep Otty's block verbatim.
  General rule: tool-managed markered blocks (conda, nvm, Otty) are left as-is *because* the tool
  rewrites them; the one-line `[[ … ]] && source` idiom is only for hand-managed integrations
  (gcloud, openclaw) that nothing re-adds.
- **Lock-race fix scoped to CI, not the helper.** `HOMEBREW_BUNDLE_JOBS=1` lives in the workflow
  env, NOT `install_from_brewfile.sh` — real-machine `./install` relies on Homebrew's serial
  default; forcing `--jobs=1` in the helper would forgo parallel speedup forever. Escape hatch if a
  real fresh install ever races: export the same var in the helper. Drop the pin once Homebrew
  ships the upstream lock-fix (Homebrew/brew#22293 / #22297) to the runner image.
- **Coordinated merge, master stays green.** No branch protection on `master` (red checks don't
  block), but honored "keep-green": merged the mutually-blocking pair #98+#96 first → master
  green → rebased #97+#95 onto green master → both went fully green (linux + macOS) → merged.

## What Didn't Work

- **A plain CI re-run does NOT fix the lock-race.** Re-ran #96's macOS job; it failed again on a
  *different* racing pair (`gitleaks`→`go`, `luarocks`→`luajit` vs. the original `go`/`luarocks`).
  The collisions are nondeterministic — only serial install fixes it deterministically. Don't
  burn re-runs hoping it clears.

## What's Next

1. **(dotfiles, low-priority) Fix the `install_omz.sh:21` arithmetic warning.** Every macOS CI run
   prints `helpers/install_omz.sh: line 21: zsh-256color: value too great for base (error token is
   "256color")`. Non-fatal (install continues, CI passes), but real: line 21 does an arithmetic
   evaluation over the OMZ plugin list and chokes on the plugin name `zsh-256color` (treats
   `256color` as a number). One-line fix (quote/guard the arithmetic). Its own small `fix/` PR.
2. **(dotfiles, housekeeping) Remove the `HOMEBREW_BUNDLE_JOBS: '1'` pin** once the upstream
   Homebrew lock-fix (Homebrew/brew#22293 / #22297) lands in the `macos-15` runner image. The
   pin's inline comment already flags this.
3. **(external, carried from 2026-07-07 handoff — unchanged):** record "Foreman" as the
   ibmcconstruction platform's official name; optional domain buys (`theforeman.io` / `foremanhq.ai`);
   Ship Sigma send-volume → `/ops/shipsigma-deliverability` calculator; optional `villavi.dev`;
   Dec 11 2026 calendar event for the 307→308 redirect flip.

## Gotchas & Watch-outs

- **Master is GREEN as of this session** — first clean macOS CI in a while. If it goes red on an
  *unchanged* commit later, suspect `macos-15` runner-image rotation (workflow header caveat #8)
  before debugging the pipeline.
- **macOS CI is now ~slower but deterministic** — serial `brew bundle` trades wall-clock for no
  flakiness. Intended.
- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`.** Otty self-manages it via
  those markers and re-appends a fresh copy on shell launch if it can't find them — #97 conformed
  it and Otty duplicated the block within one session (fixed by #99). Leave it verbatim. Because
  `zsh/zshrc` is Dotbot-symlinked to the live config, Otty's rewrites land straight in the repo
  working tree; if a duplicate ever reappears, keep the markered block and delete the extra.
- **`claude/settings.json` still goes dirty from `/model` + `/effort` churn** — standing pattern:
  on commit, revert the model-pin removal and keep only genuine additions (plugins/marketplaces).
