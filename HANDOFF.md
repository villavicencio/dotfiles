# HANDOFF — 2026-05-03 (PDT, evening)

Continuation of the same calendar day's afternoon session that shipped PR #56. Started with `/pickup` against the prior afternoon HANDOFF, then drove **PR #57 (CE trifecta PR #1b)** end-to-end: write workflow → 5 CI failure-iteration rounds → seeded-failure validation → ce-code-review with 9 reviewers → apply best-judgment fixes → green → squash-merge. Net result: **PR #57 merged** as `24209d7`, install-matrix CI now runs on every PR, 4 follow-up issues filed.

## What We Built

### PR #57 — feat(ci): install-matrix workflow + chsh CI gate (squash-merged 2026-05-04T04:19Z as `24209d7`)

7 files changed, 527 insertions, 5 deletions. The 11 branch commits (1 feat + 4 fix iterations + 2 seeded-failure + 1 revert + 3 review-fix) collapsed cleanly to one master commit.

**Core deliverables:**
- `.github/workflows/install-matrix.yml` (new, ~390 lines) — two top-level jobs (`linux:` + `macos:`), not a strategy matrix. **Linux** pulls digest-pinned `ghcr.io/villavicencio/dotfiles-ci-ubuntu@sha256:8b0b7108…3865`, runs as root in container; **macOS** runs `macos-15` bare with `actions/cache@v4` for Homebrew downloads + API. Each leg runs `./install --dry-run` then `./install` and asserts:
  - **R2**: zero-`$HOME` mutation under dry-run, via `snapshot_home()` find delta-diff that prunes runner-noise subtrees (`actions-runner`, `work`, `Library`).
  - **R3-a**: `git grep --extended-regexp '/Users/[^/]+/'` finds nothing in `'zsh/** helpers/** brew/** git/** claude/**'` (fail-closed empty-list check first).
  - **R3-b**: every `Would create symlink X -> Y` target Y exists in repo (per Dotbot v1.24.1 emitter format), with fresh-runner sanity check `created≥1` to fail loudly on output-format drift.
  - **R4**: `zsh -i -c true` exits 0.
- `install.conf.yaml:47-53` — chsh directive switched from inline `[chsh -s $(which zsh), Making zsh the default shell]` flow form to block style (the inline form's `&&` trips YAML's `&` anchor parser). Block CI-gates on `if [ "${CI:-false}" != "true" ]` so PAM auth doesn't fail on hosted macOS.
- `docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md` (new, 120 lines) — origin SC#1 evidence. Seeded `/Users/dvillavicencio/` in `helpers/install_node.sh`, both legs red-CI'd at exactly R3 assertion 1 (run `25293491791`, jobs 74148651331 + 74148651338), reverted, both legs green again on run `25293773365`.
- `claude/settings.json:81`, `claude/commands/handoff.md:13`, `claude/commands/pickup.md:21` — replaced `/Users/dvillavicencio/...` with `$HOME/...` (the original R3-a scope `'zsh/** helpers/** brew/** git/**'` excluded `claude/**`, so the matrix was silently passing despite 3 actual violations; review caught + fixed in same PR).
- `claude/skills/tmux-window-namer/SKILL.md:77` — dropped `/Users/...` literal placeholder from a doc example so the new R3-a regex wouldn't false-positive on it.

**ce-code-review pass** surfaced 12 primary findings across 9 reviewers (correctness, security, adversarial, testing, maintainability, project-standards, reliability, agent-native, learnings-researcher). 5 reviewers cross-corroborated finding #1 (macOS missing fresh-runner sanity check). 8 findings applied as fixes (4 safe_auto + 4 best-judgment); 4 deferred to follow-up issues. 27 findings suppressed below anchor 75; 4 mode-aware-demoted to soft buckets.

**Filed during review (4 follow-up issues, all open):**
- **#58** — bake `python3 + sudo` into `ci/Dockerfile` (closes the chicken-and-egg for the apt-install bootstrap step in install-matrix.yml).
- **#59** — extract install-matrix duplicated step bodies into composite action.
- **#60** — seeded-failure validation round for **R3 assertion 2** (the symlink-target-exists check has only the `created≥1` sanity check; the missing-target loop has never been red-CI'd).
- **#61** — enforce Dotbot output-format pin in install-matrix.yml.

**CI evidence trail (final):**

| Run | Tree | linux | macos | What it proves |
|---|---|---|---|---|
| `25293240970` | clean baseline | ✅ 54s | ✅ 8m32s | full assertions pass |
| `25293491791` | seeded `/Users/dvillavicencio/` | ❌ 1m6s | ❌ 10m8s | both legs fail at R3 assertion 1; Apply succeeds; R4 short-circuits |
| `25293773365` | reverted | ✅ 49s | ✅ 9m25s | revert restored green |
| `25295706232` | review fixes (final commit `c78d6d4`) | ✅ 1m18s | ✅ 10m0s | merge baseline |

## Decisions Made

- **3 RBI items at PR-open time:** fork-PR trust boundary → accept + document in caveats block (`pull_request_target` introduces worse footguns); credential-pattern detection → accept + document (gitleaks adds tooling surface for thin marginal value); caveats block → included (this was U4 in the plan).
- **Image stays minimal in ci/Dockerfile**; install-matrix.yml apt-installs `python3 sudo` at runtime as a transient bootstrap step. `#58` tracks baking into the image (chicken-and-egg with publish-ci-image — image rebuilds only fire on master push).
- **`snapshot_home()` helper duplicated across legs intentionally** — pragmatic; `#59` tracks composite-action extraction. Note that the duplication HAS already produced one silent divergence (`created≥1` was Linux-only until the code review caught it).
- **chsh CI gate strict `CI != true` match retained.** GitHub Actions sets `CI=true` literally; broadening to `CI=1`/`CI=TRUE`/`-n CI` adds complexity for theoretical callers. Accepted-as-is per best-judgment.
- **`safe.directory` written to `/etc/gitconfig` (not `~/.gitconfig`)** via `git config --system`. Survives the next-step `rm -f $HOME/.gitconfig` cleanup that's required because actions/checkout writes a regular file there during its setup.
- **`PYTHONDONTWRITEBYTECODE: '1'` at workflow `env:` level** — required because dotbot's `import yaml` writes `__pycache__/*.pyc` under the workspace, which on macOS is *inside* `$HOME=/Users/runner`. R2 delta-diff caught it as a false positive without this flag.
- **`/home/<user>/` regex extension to R3-a was tried, then reverted** — over-matched legitimate `/home/linuxbrew/.linuxbrew/` (Linuxbrew install path on Linux) and `/home/node/...` (OpenClaw container-internal path mentioned in `claude/commands/handoff.md` documentation as something to NOT use). Final: macOS-style `/Users/[^/]+/` only.
- **`R3-a` scope expansion to `claude/**`** — done after review caught 3 pre-existing violations the original scope was silently passing. `claude/settings.json`, `claude/commands/handoff.md`, `claude/commands/pickup.md` all linked by Dotbot into `~/.claude/`, so they're install-pipeline content even though they live outside `helpers/`+`zsh/`.
- **`xargs grep -lE` → `git grep --extended-regexp`** in R3-a — handles filenames with embedded whitespace; avoids xargs no-input edge case where empty file list silently passes.
- **`actions/checkout@v4.3.1` (`34e114876b…`) and `actions/cache@v4.3.0` (`0057852bfa…`)** SHA-pinned to close the supply-chain vector.
- **`permissions: contents: read`** at workflow top — least-privilege, mirrors `publish-ci-image.yml`. Closes a same-repo-PR escalation gap that the default `GITHUB_TOKEN` scope leaves open.
- **`runs-on: macos-15`** label not pinned to a specific image revision; caveat #8 added to workflow header documenting that runner-image rotation can red-CI on environmental noise.

## What Didn't Work

- **`python3-minimal`** in the apt bootstrap step — strips the stdlib, dotbot's `import json` raised `ModuleNotFoundError`. Switched to full `python3` (~50MB; pulls `libpython3-stdlib`).
- **`git config --global --add safe.directory $GITHUB_WORKSPACE`** in the Linux container — wrote to `$HOME/.gitconfig`, then the next step `rm -f $HOME/.gitconfig` deleted it. Apply step then failed with "fatal: detected dubious ownership." Switched to `--system` (writes `/etc/gitconfig`, container is root, survives `rm $HOME/.gitconfig`).
- **`replace_all=true` Edit on a duplicated step body assumed identical surrounding context** — but the macOS leg's R3-a had a slightly different comment than Linux's after sequential prior edits, so the Edit only replaced ONE leg. macOS still had the old `(/Users/|/home/)` regex with `xargs grep`, hitting `helpers/init_homebrew.sh:6`'s legitimate `/home/linuxbrew/` path. Required a follow-up commit (`c78d6d4`) to bring macOS in symmetry. **Lesson: when modifying duplicated code, factor it out FIRST or use surrounding-text-unique anchors per leg.**
- **Single-pass `replace_all=false` Edit lost the macOS R4 step body** — the old_string spanned R3 + blank line + R4, the new_string only included R3. Caught immediately on YAML re-validation; restored with `printf >>` append.
- **`/home/<user>/` regex extension** attempted to catch Linux equivalents of macOS hardcoded paths — over-matched legitimate upstream paths (Linuxbrew install dir, OpenClaw container paths in docs). Reverted.
- **Trying to install python3 separately from sudo** — first apt-install step had `python3-minimal` only, then the `apt-get install sudo` came later as a separate fix. Eventually rolled into one step (`apt-get install -y --no-install-recommends python3 sudo`).

## What's Next

1. **Issue #58 — bake python3 + sudo into ci/Dockerfile** (smallest follow-up, ~10 min end-to-end). Touch `ci/Dockerfile` to add the apt packages, push to master → `publish-ci-image.yml` republishes → capture new digest from run summary → second tiny PR updates the digest pin in `install-matrix.yml` and removes the apt-install bootstrap step. Removes ~5–10s/run from CI overhead and gets the image closer to mirroring the VPS production parity it claims.
2. **PR #1c — third leg of CE trifecta**. `docs/solutions/_index.md` + `critical-patterns.md` regen on `/handoff`. Plan exists at `docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md` (Deferred to Follow-Up Work section). New feature work, better as fresh session.
3. **Capture two new institutional learnings** as `docs/solutions/cross-machine/` files. Pure additive content; commit directly to master per memory rule:
   - `actions/checkout` writes a regular `$HOME/.gitconfig` that Dotbot's `relink: true` won't replace.
   - `PYTHONDONTWRITEBYTECODE` is required when `$GITHUB_WORKSPACE` is inside `$HOME` on macOS runners.
4. **Issues #59, #60, #61** — composite-action extraction, R3-b seeded round, Dotbot version-pin enforcement. Each is a small follow-up; can be picked up independently.

## Gotchas & Watch-outs

- **`gh run view --log-failed` doesn't work while the run is still in progress** (other legs still running). Use `gh api repos/.../actions/jobs/<job-id>/logs` to fetch a single-job's log even when the run as a whole is "in progress."
- **`replace_all=true` is a footgun on duplicated step bodies.** When two near-identical blocks have drifted comments, replace_all only matches the most-recent edit's surrounding text. If you're going to refactor duplicated code, factor it out first OR use unique surrounding-text anchors per leg.
- **macOS-15 runner $HOME contains $GITHUB_WORKSPACE.** Linux container $HOME is `/github/home` or `/root` — outside the workspace. Anything that snapshots $HOME has to prune workspace + `actions-runner/` + `Library/` on macOS, no-op on Linux.
- **`ubuntu:24.04` minimal Docker base ≠ Ubuntu Server.** Server image ships python3 + sudo as part of the base OS; minimal Docker image omits both. The install pipeline's `helpers/install_packages.sh` uses `sudo apt-get install`, so sudo has to exist on PATH (no-op trampoline as root, but the call has to resolve). `#58` tracks baking into image.
- **`actions/checkout` writes a regular `$HOME/.gitconfig`** during its safe.directory dance (visible in the cleanup log line `Copying '/github/home/.gitconfig' to '/__w/_temp/...').` Dotbot's `relink: true` only replaces existing symlinks, not regular files. Without `rm -f $HOME/.gitconfig` before `./install`, the apply step fails with "already exists but is a regular file or directory."
- **Dotbot v1.24.1 link-plugin dry-run output format**: `Would create symlink <link_name> -> <target_path>` (per `dotbot/src/dotbot/plugins/link.py:350`). R3 assertion 2 parser depends on this. **A submodule bump that changes the wording silently breaks the parser** unless `created≥1` sanity check fires (which it now does on both legs). `#61` tracks tightening the regex or enforcing a Dotbot version pin assertion.
- **Image digest pin in `install-matrix.yml` is hand-maintained.** Every `ci/Dockerfile` change requires (a) merge to master to trigger republish, (b) capture new digest, (c) follow-up PR to bump the pin. No automation today; documented in caveat block.
- **`xargs grep -lE` without `-d '\n'` or `-0` breaks on filenames with embedded spaces.** Switched to `git grep --extended-regexp` which doesn't need xargs at all and handles weird filenames natively.
- **Pre-fix R3-a scope had hardcoded `/Users/dvillavicencio/` paths in 4 tracked files** — `claude/settings.json`, `claude/commands/{handoff,pickup}.md`, and a SKILL.md placeholder. The original `'zsh/** helpers/** brew/** git/**'` scope silently excluded them. Lesson worth filing as a learning eventually: **assertion scope and assertion intent must be derivable from the same source** — the scope was a hand-maintained list that diverged from the install-pipeline-truth defined in `install.conf.yaml` link entries.
- **Carry-forward from prior sessions:** `claude/CLAUDE.md`, `claude/commands/{handoff,pickup}.md`, `claude/settings.json` are all symlinked into `~/.claude/`; edits via the live Claude UI write back through to the repo. Today we modified all of these as part of PR #57's R3-a fixes (replacing `/Users/dvillavicencio/` with `$HOME/`). Next session should treat any `M` on those as real edits per `feedback_claude_symlink_writeback.md`.
- **`.claude/scheduled_tasks.lock`** is `/loop`'s ScheduleWakeup runtime state — untracked, harness-internal. Don't commit; ignore in pickup checks.
- **Squash-merge collapsed PR #57's 11 commits into one master commit (`24209d7`).** Per-commit history preserved in PR #57's "Commits" tab if you ever need to spelunk the iteration cycle.
