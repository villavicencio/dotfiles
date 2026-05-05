# HANDOFF — 2026-05-04 (PDT)

Continuation of the same calendar day's morning session that shipped PR #57. Started with `/pickup`, captured two pending learnings as durable docs, then drove **#58 end-to-end via PR #62 + PR #64**: image bake → republish → digest capture → pin bump. PR #64 hit a 4-attempt CI fight against a recurring apt slowness inside the GH Actions Linux container; resolved by restoring (and renaming) the apt-bootstrap step rather than removing it. Net: **2 PRs merged, 2 new follow-up issues filed (#63, #65), 2 institutional learnings landed, 1 global-instruction policy section added.** Issue #58 stays open, deferred to #65.

## What We Built

### docs(solutions) — 2 cross-machine learnings (commit `b230606`, master)

Captured at session start from PR #57's "Capture two new institutional learnings" todo:

- `docs/solutions/cross-machine/actions-checkout-leaves-regular-gitconfig-2026-05-04.md` (135 lines) — `actions/checkout` writes a regular `$HOME/.gitconfig` during its setup phase. Dotbot's `relink: true` only replaces existing symlinks (intentional safety), not regular files. Fix: explicit `rm -f "$HOME/.gitconfig"` between checkout and `./install`. Also documents the companion trap: `safe.directory` must use `--system` not `--global` since `--global` writes the very file the cleanup deletes.
- `docs/solutions/cross-machine/python-bytecode-cache-falsely-fails-r2-on-macos-runners-2026-05-04.md` (113 lines) — `PYTHONDONTWRITEBYTECODE=1` at workflow `env:` level prevents Dotbot's pyyaml import from writing `__pycache__/*.pyc` next to source. On macos-15, `$GITHUB_WORKSPACE` is *inside* `$HOME=/Users/runner`, so those writes show up in R2's `snapshot_home()` delta-diff and falsely fail the assertion. Linux containers have `$HOME=/github/home` (or `/root`) outside the workspace, so the leak is invisible there. Documents why the env flag and the prune list coexist as intentional defense-in-depth.

Both committed direct to master per the docs carve-out. No PR needed.

### docs(claude) — Realtime Facts policy section (commit `c86ba98`, master)

Added 18-line "Realtime Facts" section to `claude/CLAUDE.md` between Research and Reddit Content. Routes any query phrased as "today" / "right now" / "current" / "as of this writing" or asking for prices, stock state, current external-system config, or current package versions through the `/verify-cite` skill. The skill enforces fetch-fresh + substring-assert + freshness-tag-or-decline. Phrased "is exempt for non-realtime queries" not "is silently no-op for" (per ce-code-review agent-native finding — agent is the classifier, not an automated gate).

Originally sitting unstaged in PR #62's working tree; ce-code-review flagged the scope coupling, so it was lifted out and committed standalone to master per the docs carve-out.

### PR #62 — bake python3 + sudo into ci/Dockerfile (squash-merged 2026-05-04T20:50:08Z as `6a8cd43`)

#58 step 1/2. 1 file changed (`ci/Dockerfile`), 17 insertions / 2 deletions.

- Added `python3` and `sudo` to the apt install list. Image grew ~45MB (libpython3-stdlib via the python3 metapackage).
- **Comment correction.** The prior comment claimed "sudo is intentionally not installed — it would be dead code at root and adds CVE surface." That was wrong: `helpers/install_packages.sh` invokes `sudo apt-get install` on Linux, so the binary must resolve on PATH even when the container runs as root (no-op trampoline). Without sudo, `install_packages.sh` aborts and downstream helpers cascade-fail. New 14-line comment block explicitly documents the corrected reasoning so a future reader doesn't strip sudo again as "cleanup."
- Used full `python3` not `python3-minimal` — Dotbot does `import json` / `import yaml` at startup; minimal strips libpython3-stdlib, so `import json` raises `ModuleNotFoundError`.
- ce-code-review pass (6 always-on personas: correctness/testing/maintainability/project-standards/agent-native/learnings) surfaced 1 safe_auto fix applied in-PR (commit `dea1442`: dropped premature "closed" qualifier on the #58 reference since #58 is still open). 2 P1 findings deferred to action outside the PR (CLAUDE.md scope-out; smoke-test gap).
- Image republished by `publish-ci-image.yml` on master push. New digest captured directly from GHCR via `docker buildx imagetools inspect ghcr.io/villavicencio/dotfiles-ci-ubuntu:24.04`: **`sha256:758af964844df9c58c87669d31812cbda6655e78e8c94f66387bd0338651a6d6`**.

### PR #64 — digest pin bump + locale-block correctness fixes (squash-merged 2026-05-05T01:02:04Z as `db86950`)

#58 step 2/2, **scaled back** — original goal also included deleting the runtime apt-bootstrap step, but empirically that step turned out to be load-bearing for apt warmth. Bootstrap-step removal deferred to **#65**.

What landed:
- `.github/workflows/install-matrix.yml:107` — bumped pin from `sha256:8b0b7108…3865` → `sha256:758af964…a6d6`. Refreshed surrounding comment to drop stale "PR #1a" reference and point at `docker buildx imagetools inspect` for digest capture.
- `.github/workflows/install-matrix.yml:108-126` — renamed "Install bootstrap deps (python3, sudo)" → "Warm up apt cache" and reduced body from `apt-get update -qq && apt-get install -y --no-install-recommends python3 sudo` to just `apt-get update -qq` (python3+sudo are in the image now). Comment documents the empirical reason it was kept and points at #65.
- `install-linux.conf.yaml:32-46` — locale block correctness:
  - Added `sudo apt-get update -qq` before `sudo apt-get install -y locales` (was always-needed; surfaces as "Unable to locate package locales" on a fresh apt cache).
  - Pass `DEBIAN_FRONTEND=noninteractive` *through* sudo on the locales install (sudo's `env_reset` strips the env var set by ci/Dockerfile, and the locales postinst is famously interactive — was hanging the job on a debconf menu).

### chore(claude) — ssh allowlist addition (commit `33d50c3`, master)

Added `Bash(ssh root@openclaw-prod*)` to `claude/settings.json` permissions allowlist. /pickup Step 2c, /handoff Step 5/6, perm-drift checks, container health probes all run that command once or twice per session. Eliminates the per-invocation prompt.

## Decisions Made

- **Two-PR sequence for #58 was correct as planned.** The chicken-and-egg between `publish-ci-image.yml` (master-push trigger only) and `install-matrix.yml` (consumes the image digest) means the bake (PR #62) and the consume (PR #64) cannot be a single atomic commit if you want CI to pass on the PR itself. The issue body had pre-named this; PR #62's description reproduced the sequencing.
- **Don't re-strip sudo as "cleanup."** The corrected Dockerfile comment block (~14 lines) is intentionally verbose because the prior comment was confidently wrong and got merged once already. Comment names the failure mode (`install_tmux.sh: tmux: command not found` cascade) and references closed issue #58 so a future reader has the why.
- **Pivoted PR #64 scope** after 3 failed attempts at the network-config angle (conf-d IPv4 force, inline `-o` opts, http timeout cap). Restored the bootstrap step (renamed to make warm-up purpose explicit) instead of fighting apt's behavior. Better to ship the digest bump + correctness fixes and defer the warm-up-removal half cleanly than to keep iterating on a network problem that may not be solvable from the install pipeline.
- **`claude/CLAUDE.md` Realtime Facts section committed direct to master,** not bundled into PR #62. ce-code-review's maintainability + project-standards reviewers both flagged the scope coupling. Memory rule says additive docs go direct.
- **Issue #58 stays open** until #65 lands and the warm-up step can be genuinely removed. PR #64 only partially fulfills #58's acceptance ("Install bootstrap deps step removed"). Comment on #58 explains the deferral.
- **Skipped the Stage 5b validation pass on ce-code-review.** Interactive mode default routing skips validators (per the skill — only File-tickets option C runs them). This was correct routing for the small diff.
- **`docker buildx imagetools inspect ghcr.io/<owner>/dotfiles-ci-ubuntu:24.04`** is the canonical way to capture the published digest, not `gh run view --json jobs -q '.jobs[].outputs.digest'`. The CLI doesn't expose job-level `outputs:` in its `--json jobs` schema. GHCR is the source of truth.

## What Didn't Work

- **`Acquire::ForceIPv4 "true";` written to `/etc/apt/apt.conf.d/99force-ipv4`** at the start of the locale shell block (run 25346313051). apt-get update completed in ~2 min (was 18 min on the prior attempt without the fix), but apt-get install in `helpers/install_packages.sh` still hit ~60s/connection delays through ~10 parallel slots before the 20-min cap.
- **Inline `-o Acquire::ForceIPv4=true -o Acquire::http::Timeout=20`** on every apt invocation (run 25347298749). Made it worse — apt-get update -qq hung silently for the entire 20-min window with zero output. Hypothesis: the timeout=20 caused something to spiral into infinite retry, but the silent hang made it impossible to confirm without stripping `-qq`.
- **`python3-minimal`** in the bootstrap step (carry-forward from PR #57) — strips the stdlib, dotbot's `import json` raises `ModuleNotFoundError`. Already documented; PR #62 uses full `python3`. Worth reiterating because it's a tempting "size optimization" any future maintainer could revisit.
- **Trying to delete the bootstrap step entirely** in PR #64 (4 CI attempts: runs `25343189848`, `25344420787`, `25346313051`, `25347298749` — first three failed at apply with locale issues, fourth at 20m timeout). Each attempt taught us something but didn't unblock the deletion. Final pivot was to keep the step (renamed) and file #65.

## What's Next

1. **Issue #65 — investigate apt warmth.** Highest leverage. Resolves the 12-min Linux CI back to <2 min and lets us truly close #58. Issue body has the full empirical record (3 failed network-config approaches with run IDs + timestamps) and 4 hypotheses to test. Suggested first probe: drop `-qq` on apt-get update so the slow-path is observable. Then time `getent hosts archive.ubuntu.com` repeatedly with and without the warm-up.
2. **PR #1c — third leg of CE trifecta.** `docs/solutions/_index.md` + `critical-patterns.md` regen on `/handoff`. Plan exists at `docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md` (Deferred to Follow-Up Work section). New feature work, better as fresh session.
3. **Issues #59 / #60 / #61 / #63** — composite-action extraction, R3 assertion 2 seeded validation, Dotbot output-format pin, publish-ci-image smoke test. Each is a small follow-up; can be picked up independently. #63 is particularly worth doing soon since #65's investigation may reveal that an image-level fix is needed, and a smoke-test guards against image regressions.
4. **`actions/checkout` Node 20 deprecation warning** is now showing on every CI run. Action can be bumped to a Node 24 version when one is available; currently informational only (the deadline is June 2nd, 2026 per GH's own message).

## Gotchas & Watch-outs

- **Linux CI is now ~12 min** (was ~54s on PR #62 era). Network slowness is real and consistent across runs today. Every future PR pays this. #65 is the cure.
- **The "Warm up apt cache" step is misleadingly named** if you read just the body (`apt-get update -qq`). It's named for *why* it exists (network warm-up), not what the command does. The name is intentional — it's documenting the load-bearing role for future maintainers. Don't rename it back to something descriptive of the body alone.
- **`docker buildx imagetools inspect` requires the registry to expose the manifest publicly.** publish-ci-image.yml flips visibility to public on every run via `gh api -X PATCH .../visibility`. If that ever fails, the digest capture step in step 2/2 of any future bake-republish-bump cycle will need an authenticated path.
- **Image digest in `install-matrix.yml:107` is hand-maintained.** Same caveat as PR #57's HANDOFF; reaffirmed today. Every `ci/Dockerfile` change requires (a) merge to master to trigger republish, (b) capture new digest, (c) follow-up PR to bump the pin. No automation today.
- **`claude/CLAUDE.md`, `claude/commands/*.md`, `claude/settings.json` are symlinked into `~/.claude/`** — edits via the live Claude UI write back through to the repo. Today we modified `claude/CLAUDE.md` (Realtime Facts section) and `claude/settings.json` (ssh allowlist), both committed to master direct. Per `feedback_claude_symlink_writeback.md`, treat any `M` on those as real edits.
- **`.claude/scheduled_tasks.lock`** is /loop's ScheduleWakeup runtime state — untracked, harness-internal. Don't commit; ignore in pickup checks.
- **`.forge-pending`** drained at session start (4 items pushed: 2 patterns, 1 comm, 1 cadence). File is gone. Future sessions will only see this file if `/handoff` Step 5's SSH push fails.
- **`Acquire::ForceIPv4 "true";`** is not currently in `/etc/apt/apt.conf.d/` on the image. The conf-file write was reverted as part of the PR #64 pivot. If you bring it back as part of #65 work, also bring back the visible `tee` (drop `>/dev/null`) so CI logs confirm the write.
- **The 3-min "Warm up apt cache" step** is also paying the network slowness. Don't be misled by the green CI — the warm-up step is itself slow. The downstream Apply step is what was previously hitting 20m without it; with it, Apply is ~9 min. Cumulative ~12 min total.
- **Issue #58 still references the closed PRs (#62, #64) but is open.** Comment explains the deferral. When #65 lands and the warm-up step is removed, close #58 in the same PR that removes it.
