---
title: feat: CI install matrix on every PR
type: feat
status: active
date: 2026-05-03
origin: docs/brainstorms/2026-05-02-compound-engineering-trifecta-requirements.md
---

# feat: CI install matrix on every PR

## Summary

PR #1 of the compound-engineering trifecta — **split into two sequential PRs** (#1a and #1b) due to a chicken-and-egg between the ghcr.io image publisher and the install-matrix workflow that consumes it. PR #1a ships `ci/Dockerfile` + `.github/workflows/publish-ci-image.yml` (the image publisher) and merges first; once the image is published and made public, PR #1b ships `.github/workflows/install-matrix.yml` + the `install.conf.yaml` chsh skip + an inline-comment architectural-caveats block. Both legs assert: mutation-free dry-run, exit-zero install, no hardcoded user paths in install-pipeline files, expected symlinks resolve via Dotbot dry-run output, and `zsh -i -c true` exits cleanly. Image is pinned to digest, not mutable tag.

---

## Problem Frame

The dotfiles install pipeline is currently untested across machines (origin Problem Frame). "Did this PR break fresh-host bootstrap?" only gets answered months later when the user wipes a real machine — exactly the high-stakes moment the test should already have run. PR #1 closes that gap by validating the install pipeline end-to-end on every PR against master, on the two OS targets that mirror production (Ubuntu 24.04 = VPS; `macos-15` arm64 = personal Mac).

---

## Requirements

- R1. New GitHub Actions workflow runs the install pipeline on every PR against master, on Ubuntu 24.04 and `macos-15` *(carries origin R1)*.
- R2. Both legs run `./install --dry-run` first and assert zero filesystem mutations on a fresh `$HOME` *(carries origin R2)*.
- R3. Both legs then run `./install` and assert: exit zero, no hardcoded `/Users/<user>/` paths in tracked install-pipeline files (`zsh/`, `helpers/`, `brew/`, `git/`), all Dotbot-declared symlinks resolve to files inside the repo *(carries origin R3)*.
- R4. Both legs spawn `zsh -i -c true` post-install and assert it exits cleanly *(carries origin R4)*.
- *(R5 was originally a requirement; reclassified as Success Criterion — see Success Criteria below.)*
- R6. Existing `Dockerfile` at repo root is removed; new `ci/Dockerfile` is the basis for the Linux container leg, targeting `ubuntu:24.04`, root user, only the bootstrap deps `helpers/install_packages.sh` does not install itself *(carries origin Dependencies clarification)*.
- R7. CI does not validate machine-local overrides (`~/env.sh`, `~/.gitconfig.local`, `~/.ssh/config`), Tailscale steps, or docker-desktop runtime — these are documented architectural caveats. The `chsh` step has an explicit skip mechanism (see Key Technical Decisions).

**Origin actors:** A1 (repo author), A2 (PR reviewers — `ce-code-review`, `ce-learnings-researcher`), A3 (GitHub Actions runner)
**Origin flows:** F1 (CI install matrix on every PR)
**Origin acceptance examples:** AE1 (covers R2), AE2 (covers R3); AE4 (covers origin R9 — out of PR #1 scope; lands in PR #3 plan)

---

## Success Criteria

- **Seeded-failure validation (carries origin Success Criteria #1).** PR #1b includes a temporary commit on its own branch that breaks bootstrap in one of the bug classes named in origin SC#1 (cross-platform divergence, fresh-`$HOME` mutation, or shell-startup regression). The install matrix red-CIs correctly on both legs; the failure log identifies the assertion that fired. The seeded commit is reverted before merge. **This is manual discipline, not workflow code** — there is no `seeded_failure` workflow input or step. Evidence is captured durably in `docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md` (or similar) so future readers can see what was tested.
- A future PR introducing a real install-pipeline regression in any of those bug classes should be red-CI'd by the matrix before merge. Verifiable empirically in the months following PR #1b.

---

## Scope Boundaries

- **PR #2 and PR #3 are out of scope.** `helpers/_test.sh` test harness and `docs/solutions/_index.md` + `critical-patterns.md` are sibling PRs with their own plans.
- **No work-Mac corporate-SSL CI leg.** Origin defers this; would require a self-hosted runner or cert-redaction strategy.
- **No deep-behavioral assertions.** Specific brew package versions, exact command output strings, browser screenshot diffs — too flaky for cold runners.
- **No `helpers/doctor.sh` standalone command.** Subsumed by the CI matrix per origin Scope Boundaries.
- **No caching of `/opt/homebrew/Cellar` or `/opt/homebrew/Caskroom`.** Install destinations cache poorly; download cache only.
- **No Tailscale steps in CI.** Hosted runners aren't on the tailnet.
- **No docker-desktop runtime testing.** Cask installs but daemon doesn't start in CI; acceptable.
- **No mise / op inject / per-host Brewfile / bootstrap.sh.** Sibling ideation survivors with their own brainstorms.

### Deferred to Follow-Up Work

- **PR #2 (helpers/_test.sh harness)** — separate plan; CI invocation of the harness lands in PR #2.
- **PR #3 (solutions index + critical-patterns)** — separate plan; the `/handoff` regen integration lives there.
- **Image-digest auto-update workflow** — defer; PR #1a manually captures the SHA digest from the first publish run, the user updates `install-matrix.yml` in PR #1b to pin to it. Automating digest round-tripping (publish → commit-back → install-matrix references new digest) is a future workflow.
- **CI assertion script extraction** — keep assertions inline for PR #1b; if complexity grows in PR #2/PR #3, extract to `scripts/ci-assertions.sh` for local + CI reuse.
- **CLAUDE.md / README CI section** — origin had no requirement for it. Architectural caveats land as an inline comment block at the top of `install-matrix.yml` instead of a separate doc edit. Standalone CI documentation can be a follow-up if reviewers ask for it.
- **Credential-pattern scanning** (gitleaks or curated regex) — the R3 grep covers paths only, not API keys / OAuth tokens / GCP service-account JSON. Decide later: add to PR #1b scope, separate PR, or accept the gap. (See Open Questions.)

---

## Context & Research

### Relevant Code and Patterns

- `.github/workflows/sync-vps.yml` — existing workflow; pattern reference for `workflow_dispatch` inputs, regex-guarded ssh interpolation, `${{ steps.X.outputs.Y }}` capture, `GITHUB_STEP_SUMMARY` reporting, `concurrency` group syntax.
- `install` (33-line wrapper) — Darwin/Linux dispatcher; exports `DOTFILES_DRY_RUN=1` when `--dry-run`/`-n` is passed; runs vendored Dotbot.
- `install.conf.yaml` (Darwin) and `install-linux.conf.yaml` (Linux) — Dotbot configs invoked by `install`. `install.conf.yaml` line 41 currently has `[chsh -s $(which zsh), Making zsh the default shell]` — must be CI-gated (see Key Technical Decisions).
- `brew/Brewfile` (95 formulas + 3 casks) — cache-key input on macOS; verified at plan time to contain no `mas` entries.
- `helpers/install_*.sh` (11 scripts) — bash 3.2-compatible style; `DOTFILES_DRY_RUN` guard pattern at the top of state-mutating helpers.
- `dotbot/` submodule (v1.24.1) — checkout step must use `submodules: recursive`. Dotbot v1.23+ supports `--dry-run` natively and emits `Would link / Would create` lines that are the basis for the symlink-resolution assertion in R3 (see U3 Approach below).
- `Dockerfile` at repo root — Sep 2024, `ubuntu:20.04`, `tester` user. Verified unused by anything in the repo; replaced by `ci/Dockerfile` (R6).

### Institutional Learnings

- `docs/solutions/best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md` — the bug class motivating the seeded-failure validation.
- `docs/solutions/cross-machine/sync-vps-dry-run-previews-current-head.md` — dry-run-as-preview semantics (Dotbot v1.23+ native dry-run is mutation-free).
- `docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md` — confirms vendored Dotbot v1.24.1 supports `--dry-run`.
- `docs/solutions/code-quality/zsh-dash-i-c-exit-false-positive-health-check.md` — use `zsh -i -c true`, not `zsh -i -c exit`.

### External References

- [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) — `macos-15` is arm64 (3-core M1, 7 GB RAM); pre-installed Homebrew, git, bash 3.2, zsh.
- [Running jobs in a container](https://docs.github.com/en/actions/using-jobs/running-jobs-in-a-container) — `jobs.<id>.container.image` requires a pre-built pullable image.
- [actions/cache README (v4)](https://github.com/actions/cache) — `actions/cache@v4` is the safe pin.
- [Homebrew/actions setup-homebrew](https://github.com/Homebrew/actions/blob/master/.github/workflows/setup-homebrew.yml) — env-var reference (`HOMEBREW_NO_AUTO_UPDATE`, `HOMEBREW_NO_INSTALL_CLEANUP`).
- [docker/build-push-action](https://github.com/docker/build-push-action) — used in `publish-ci-image.yml` to build and push `ci/Dockerfile`.
- [GHCR package visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility) — first publish creates packages as private by default.

---

## Key Technical Decisions

- **Split PR #1 into PR #1a (image-publish prerequisites) + PR #1b (install-matrix).** Reviewer-flagged P0: a single PR cannot ship both `publish-ci-image.yml` and `install-matrix.yml` because the image only publishes on `push: branches: [master]`, not pull_request. PR #1a merges → publish workflow fires on master → image becomes pullable → PR #1b opens, references the now-published image. Each PR is independently mergeable and reviewable. R12 (origin "each PR ships independently") is preserved.
- **Two separate top-level jobs in install-matrix (`linux:` + `macos:`), not a strategy matrix.** Cleaner than mixing container-based + bare-runner targets in one matrix; sidesteps GH Actions matrix-context limitations.
- **Linux container image is pinned to digest, not mutable tag.** Originally deferred to "follow-up if image churn becomes an issue"; reviewer-flagged P1 as supply-chain injection vector. Install-matrix references `ghcr.io/${{ github.repository_owner }}/dotfiles-ci-ubuntu@sha256:<digest>`. After PR #1a publishes the image, the user captures the digest from the publish workflow's run summary and pins it manually in PR #1b's `install-matrix.yml`. Subsequent image republishes require a separate PR to update the pin. Trade: explicit churn cost in exchange for supply-chain integrity.
- **Image owner uses `${{ github.repository_owner }}` expression**, not literal username. Owner-rename or repo-transfer doesn't break CI.
- **First-publish ghcr.io visibility flip is documented as a one-time operational step.** GHCR creates new packages private by default; install-matrix needs anonymous-public access. After PR #1a's first publish, the user (or a follow-up `gh api -X PATCH /user/packages/container/dotfiles-ci-ubuntu --field visibility=public` step) flips it to public. One-time; subsequent publishes inherit the setting.
- **`chsh -s $(which zsh)` in `install.conf.yaml` is CI-gated.** PR #1b includes a one-line edit to `install.conf.yaml`'s shell directive: `[bash -c '[[ "${CI:-false}" != "true" ]] && chsh -s $(which zsh)', Making zsh the default shell (skipped in CI)]`. Avoids the chsh PAM-auth failure on hosted macOS runners that would otherwise fail R3's exit-zero assertion.
- **R3 assertions are scoped CI assertions** — *not* claimed as "smoke-level." 5 distinct checks: mutation-free dry-run (R2), exit-zero `./install` (R3), no hardcoded user paths via grep (R3), Dotbot-declared symlinks resolve inside repo (R3), `zsh -i -c true` (R4). Symlink resolution uses Dotbot's `--verbose` link-output as the source-of-truth (no YAML parsing); link-target verification uses a portable bash-only `cd && pwd -P` resolver (no python3 dependency in `ci/Dockerfile`).
- **R3 grep uses fail-closed semantics.** `git ls-files -- 'zsh/**' 'helpers/**' 'brew/**' 'git/**'` is asserted non-empty before piping to `xargs grep`; an empty file list (scoping bug) fails the step rather than silently passing.
- **R2 assertion uses delta semantics, not absolute count.** `pre=$(find $HOME -mindepth 1 -print 2>/dev/null | sort); ./install --dry-run; post=$(find $HOME -mindepth 1 -print 2>/dev/null | sort); diff <(echo "$pre") <(echo "$post")` — works on a non-empty `$HOME` (the macos-15 runner's `$HOME` already has runner setup state).
- **macOS Brew cache: download tarballs + API metadata only, keyed on `runner.os` + `runner.arch` + `hashFiles('brew/Brewfile', 'helpers/**')`.** Helper changes that mutate brew state bust the cache; restore-keys fallback is `${{ runner.os }}-${{ runner.arch }}-brew-` only (no Brewfile-hash subset, which would let a poisoned cache survive Brewfile changes).
- **Public repo = free CI.** Don't optimize for cost; optimize for runtime. Cold-cache macOS run is 15-30min; warm is 5-10min.
- **Triggers: `pull_request: branches: [master]` + `workflow_dispatch`.** `paths-ignore` excludes `docs/**`, `**.md`, `claude/**/*.md` (narrowed from `claude/**` so executable code under `claude/hooks/`, `claude/statusline-command.sh`, `claude/settings.json` triggers CI).
- **Seeded-failure validation is manual discipline, not workflow code.** No `seeded_failure` `workflow_dispatch` input; no optional-failure step. Standard practice across CI-mature repos: temporary commit on PR branch breaks bootstrap, CI goes red, the failure log is inspected to confirm it red-CI'd for the *right* reason, the seeded commit is reverted before merge. PR #1b's seeded-failure round produces a durable evidence doc under `docs/solutions/cross-machine/`.
- **`HOMEBREW_NO_AUTO_UPDATE=1` + `HOMEBREW_NO_INSTALL_CLEANUP=1`** as job-level env on the macOS job. Cuts metadata churn.
- **Submodule checkout with `submodules: recursive`** on both jobs.
- **No `mas` Brewfile gating in PR #1b.** Verified absent at plan time.

---

## Open Questions

### Resolved During Planning

- **One PR or two?** Two: PR #1a (U1+U2) + PR #1b (U3+U4). Resolves the chicken-and-egg.
- **Linux leg: `runs-on: ubuntu-24.04` directly or custom container?** Custom container, published to ghcr.io, pinned by digest. VPS production-parity (root user, minimal Ubuntu base).
- **Where does the new Dockerfile live?** `ci/Dockerfile` (new path).
- **Cache strategy?** Download cache only, keyed on Brewfile hash + helpers/** + arch.
- **`paths-ignore` scope?** `docs/**`, `**.md`, `claude/**/*.md`. Narrowed to *.md so executable code under claude/ still triggers CI.
- **`seeded_failure` exposed as `workflow_dispatch` input?** No — manual discipline only; no workflow-level input or step. Origin Success Criteria #1 describes a process, not a code path.
- **Image-tag strategy?** SHA-pinned (`@sha256:<digest>`), not mutable `:24.04`. Updated manually after each image publish.
- **chsh skip mechanism?** Wrap in CI-env-gate at the `install.conf.yaml` shell-directive level.
- **R3 grep semantics?** Fail-closed: assert non-empty file list before grep.
- **R2 assertion semantics?** Delta (`diff` of pre/post `$HOME` listings), not absolute zero count.
- **Username portability?** `${{ github.repository_owner }}` expression.

### Deferred to Implementation

- **Image-digest update mechanism** — manual for now. Capture digest from `publish-ci-image.yml`'s run summary, edit `install-matrix.yml` in PR #1b. Future PR can automate via a digest-round-trip workflow.
- **First-publish visibility flip** — manual UI step OR `gh api -X PATCH` step in publish-ci-image.yml's first run. Decided at PR #1a implementation time.
- **Cache-restore timeout values** — `actions/cache@v4` defaults are typically fine.
- **Brewfile cask download cost** — actual cold-run timing only verified at first CI run.

### Resolve Before Implementation (PR #1b)

- **Fork-PR trust boundary.** Public repo means a fork PR modifying `brew/Brewfile` runs that formula on a hosted runner. Personal-author repo with single-author write makes practical risk low. Decide: (a) tighten via `pull_request_target` + first-time-contributor approval gate, or (b) accept and explicitly document in the workflow YAML's comment block that fork PRs run with the same trust as own PRs.
- **Credential pattern detection** (R3 expansion). The current R3 grep covers `/Users/[^/]+/` paths only — not API keys, OAuth tokens, JWT blobs, or GCP service-account JSON. Decide: (a) add gitleaks or curated regex to PR #1b's R3 step, (b) defer to a follow-up PR, or (c) accept the gap and document.
- **Inline architectural-caveats comment block in `install-matrix.yml`.** Origin had no CLAUDE.md update requirement. Decide: (a) add a `# CI does not validate ~/env.sh, ~/.gitconfig.local, Tailscale, chsh, docker-desktop runtime` comment block at the top of the workflow file, or (b) skip and leave architectural caveats undocumented.

---

## Output Structure

    .github/
      workflows/
        sync-vps.yml             # existing, unchanged
        publish-ci-image.yml     # NEW (U2 — PR #1a)
        install-matrix.yml       # NEW (U3 — PR #1b)
    ci/
      Dockerfile                 # NEW (U1 — PR #1a) — replaces repo-root Dockerfile
    install.conf.yaml            # MODIFIED (U3 PR #1b — chsh CI gate)

The repo-root `Dockerfile` is removed in U1 (verified unused). All other repo content is unchanged.

---

## Implementation Units

- U1. **`ci/Dockerfile` rewrite (and remove repo-root `Dockerfile`)** — *PR #1a*

**Goal:** Replace the structurally-unusable repo-root `Dockerfile` with a new minimal `ci/Dockerfile` matching the VPS production target.

**Requirements:** R6

**Dependencies:** none

**Files:**
- Create: `ci/Dockerfile`
- Delete: `Dockerfile` (at repo root)

**Approach:**
- Base: `ubuntu:24.04` (matches VPS).
- Run as root (matches VPS install runbook).
- Pre-install only the minimum bootstrap deps: `git`, `zsh`, `sudo`, `ca-certificates`, `curl`. Use `DEBIAN_FRONTEND=noninteractive` and `apt-get` cache cleanup in the same RUN layer.
- Set `WORKDIR /root`.
- Do NOT copy the dotfiles repo into the image — the workflow mounts via `actions/checkout` + container working-directory mount.
- Do NOT install `python3` — the symlink-resolution assertion uses bash-only `cd && pwd -P`, avoiding the dependency.

**Test scenarios:**
- Test expectation: none — Dockerfile is a CI asset, exercised by U3's matrix run.

**Verification:**
- `ci/Dockerfile` exists and builds locally with `docker build -t test ci/`.
- `docker run --rm -v $(pwd):/work -w /work test ./install --dry-run` produces no errors and zero `$HOME` mutations.
- The repo-root `Dockerfile` no longer exists.

---

- U2. **`.github/workflows/publish-ci-image.yml` — image publish workflow** — *PR #1a*

**Goal:** Publish `ci/Dockerfile` to `ghcr.io/${{ github.repository_owner }}/dotfiles-ci-ubuntu:24.04` on master pushes touching the Dockerfile, and emit the SHA digest in the run summary so PR #1b can pin to it.

**Requirements:** R1 (the install-matrix workflow depends on this image)

**Dependencies:** U1 (Dockerfile must exist before publish can build it)

**Files:**
- Create: `.github/workflows/publish-ci-image.yml`

**Approach:**
- Triggers: `push: branches: [master]; paths: ['ci/Dockerfile']` and `workflow_dispatch`.
- One job, `runs-on: ubuntu-24.04`. Permissions: `packages: write`, `contents: read`.
- Steps: `actions/checkout@v4` → `docker/login-action@v3` (auth to ghcr.io with `secrets.GITHUB_TOKEN`) → `docker/setup-buildx-action@v3` → `docker/build-push-action@v6` with `context: ./ci`, `tags: ghcr.io/${{ github.repository_owner }}/dotfiles-ci-ubuntu:24.04`, `push: true`.
- Capture `${{ steps.<build-id>.outputs.digest }}` and write it to `GITHUB_STEP_SUMMARY` in a copy-pasteable form so the user can pin it in PR #1b's install-matrix.yml.
- `concurrency: group: publish-ci-image; cancel-in-progress: false`.
- After first successful run on master, the package needs visibility flipped to public (one-time): either via a `gh api -X PATCH /user/packages/container/dotfiles-ci-ubuntu --field visibility=public` step using `secrets.GITHUB_TOKEN`, or manually via the GitHub Packages UI. Document the chosen path in the workflow's run summary or in the PR #1a description.

**Patterns to follow:**
- `sync-vps.yml`'s `concurrency` syntax, `GITHUB_STEP_SUMMARY` reporting style.

**Test scenarios:**
- Happy path: `push` to master touching `ci/Dockerfile` triggers the workflow; image publishes to `ghcr.io/<owner>/dotfiles-ci-ubuntu:24.04`; the run summary contains the SHA digest.
- Edge case: `push` to master not touching `ci/Dockerfile` does NOT trigger.
- Manual: `workflow_dispatch` re-publishes successfully.
- Integration: after first publish, package visibility is public (manual flip OR automated via gh api).

**Verification:**
- After PR #1a merges, `publish-ci-image` runs automatically.
- `docker pull ghcr.io/<owner>/dotfiles-ci-ubuntu:24.04` succeeds anonymously from a developer machine.
- The SHA digest is captured for PR #1b.

---

- U3. **`.github/workflows/install-matrix.yml` + `install.conf.yaml` chsh gate** — *PR #1b*

**Goal:** Run `./install --dry-run` then `./install` on Ubuntu 24.04 (container, digest-pinned) + macOS 15 (bare runner) per PR; add CI-gated chsh to `install.conf.yaml`.

**Requirements:** R1, R2, R3, R4, R7

**Dependencies:** U2 (image must be published, public, and digest pinned). PR #1b can only open after PR #1a merges and the publish workflow's first run has completed and image visibility is flipped to public.

**Files:**
- Create: `.github/workflows/install-matrix.yml`
- Modify: `install.conf.yaml` — line 41's `chsh` shell directive becomes CI-gated:
  - From: `[chsh -s $(which zsh), Making zsh the default shell]`
  - To: `[bash -c '[[ "${CI:-false}" != "true" ]] && chsh -s $(which zsh) || echo "skipping chsh in CI"', Making zsh the default shell (skipped in CI)]`

**Approach:**
- Triggers: `pull_request: branches: [master]; paths-ignore: ['docs/**', '**.md', 'claude/**/*.md']` + `workflow_dispatch`.
- Two jobs:
  - `linux:` — `runs-on: ubuntu-24.04`, `container.image: ghcr.io/${{ github.repository_owner }}/dotfiles-ci-ubuntu@sha256:<digest>` (digest captured from U2).
  - `macos:` — `runs-on: macos-15`, with `actions/cache@v4` for Homebrew downloads + API.
- Each job's steps:
  1. `actions/checkout@v4` with `submodules: recursive`.
  2. (macOS only) `actions/cache@v4`: paths `~/Library/Caches/Homebrew/downloads` + `~/Library/Caches/Homebrew/api`; key `${{ runner.os }}-${{ runner.arch }}-brew-${{ hashFiles('brew/Brewfile', 'helpers/**') }}`; restore-keys `${{ runner.os }}-${{ runner.arch }}-brew-`.
  3. (macOS only) Set `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_INSTALL_CLEANUP=1` as `env:` at job level. Set `CI=true` (already set by GH Actions, but pinned for clarity so the chsh gate fires).
  4. **R2 assertion (mutation-free dry-run, delta semantics):**
     ```
     pre=$(find "$HOME" -mindepth 1 -print 2>/dev/null | sort)
     ./install --dry-run
     post=$(find "$HOME" -mindepth 1 -print 2>/dev/null | sort)
     diff <(echo "$pre") <(echo "$post") || { echo "::error::dry-run mutated \$HOME"; exit 1; }
     ```
  5. **Run `./install`** (the real install).
  6. **R3 assertion 1 (no hardcoded user paths, fail-closed):**
     ```
     files=$(git ls-files -- 'zsh/**' 'helpers/**' 'brew/**' 'git/**')
     [ -n "$files" ] || { echo "::error::scoping returned no files"; exit 1; }
     if echo "$files" | xargs grep -lE '/Users/[^/]+/'; then
       echo "::error::found hardcoded user path(s) in install-pipeline files"
       exit 1
     fi
     ```
  7. **R3 assertion 2 (Dotbot-declared symlinks resolve inside repo):** capture `./install --dry-run`'s `--verbose` output (Dotbot v1.23+ logs each `Would link <target> -> <source>` operation). Parse the `<source>` path from each line, verify it exists in the repo via `[ -e "<source>" ]`. No YAML parsing; portable across Linux + macOS via bash-only operators.
  8. **R4 assertion (`zsh -i -c true`):** spawn `zsh -i -c true`; assert exit 0.
- Architectural-caveats comment block at top of `install-matrix.yml`: notes that CI does not validate `~/env.sh` / `~/.gitconfig.local` / `~/.ssh/config` / Tailscale / chsh / docker-desktop runtime; these are machine-local concerns. Whether to also add a CLAUDE.md section is deferred (see Open Questions).

**Patterns to follow:**
- `sync-vps.yml` — `GITHUB_STEP_SUMMARY` style, regex-guarded shell interpolation, output-capture conventions.
- `actions/checkout@v4` + `submodules: recursive`.

**Test scenarios:**
- Covers AE1 (Happy path R2): given fresh runner, `./install --dry-run` then `find $HOME` delta is empty (per concrete shell in step 4).
- Covers AE2 (Happy path R3): given `./install` ran, file list is non-empty AND grep returns no matches.
- Edge case: scoping bug returns empty file list → step exits non-zero with "scoping returned no files" (fail-closed).
- Edge case: linux container runs as root with `$HOME=/root` — dry-run delta still zero.
- Edge case: macOS leg with `BREW_PREFIX=/opt/homebrew` (arm64 default) — no hardcoded `/usr/local/` references.
- Error path: a PR introducing `read || return 0` into a helper trips `zsh -i -c true` (exit non-zero downstream). Validates seeded-failure dance.
- Error path: a PR introducing a hardcoded `/Users/dvillavicencio/` in `helpers/install_node.sh` is caught by R3 assertion 1.
- Integration: both legs complete green; workflow conclusion is "passed."
- Integration (seeded-failure): a deliberate-break commit on PR #1b's branch red-CIs at the expected step on both legs; logs identify the assertion that fired; the commit is reverted; next CI run is green; durable evidence doc is created.

**Verification:**
- After PR #1a merges, image is published and public.
- PR #1b opens with the image digest pinned in `install-matrix.yml`.
- Both legs run green on the first non-seeded commit.
- Seeded-failure validation produces durable evidence under `docs/solutions/cross-machine/`.

---

- U4. **(Reduced)** Inline architectural-caveats comment block at the top of `install-matrix.yml` — *PR #1b*

**Goal:** Make the architectural caveats (R7) discoverable in the workflow file itself, without a separate `CLAUDE.md` or `README.md` edit.

**Requirements:** R7

**Dependencies:** U3

**Files:**
- Modify: `.github/workflows/install-matrix.yml` (comment-block addition only)

**Approach:**
- Top of the workflow file: a 5-10 line YAML comment block listing the architectural caveats (CI does not validate `~/env.sh`, `~/.gitconfig.local`, `~/.ssh/config`, Tailscale steps, chsh, docker-desktop runtime; first-publish visibility flip is one-time; image is digest-pinned and updated manually).
- Optional: if the user later requests a standalone CI section in CLAUDE.md or README, that's a follow-up PR. For PR #1b scope, the comment block is sufficient.

**Test scenarios:**
- Test expectation: none — comment-block change.

**Verification:**
- A reader opening `install-matrix.yml` cold understands the architectural caveats from the comment block alone, without consulting other docs.

---

## System-Wide Impact

- **Interaction graph:** `publish-ci-image.yml` and `install-matrix.yml` are independent of `sync-vps.yml`. No shared secrets or concurrency groups. `publish-ci-image` consumes `secrets.GITHUB_TOKEN`; `install-matrix` consumes the public ghcr.io image (no auth needed for read).
- **Error propagation:** Each leg of `install-matrix` is independent (top-level jobs). A Linux failure does not cancel the macOS leg.
- **State lifecycle risks:** None. CI is read-only against the repo state and writes only to ephemeral runner `$HOME`. `publish-ci-image` writes to ghcr.io.
- **API surface parity:** N/A.
- **Integration coverage:** R3's symlink-resolution via Dotbot dry-run output is the cross-layer check. R2's mutation-free dry-run verifies the install wrapper's `DOTFILES_DRY_RUN` plumbing across all helpers.
- **Unchanged invariants:** `sync-vps.yml`'s behavior, the install pipeline's runtime semantics, the Dotbot v1.24.1 `--dry-run` contract — all preserved.

---

## Risks & Dependencies

| Risk | Mitigation |
|---|---|
| PR #1b's first install-matrix run fails because PR #1a's image visibility wasn't flipped to public | PR #1a's workflow includes a step (or a documented manual operation) to flip visibility immediately after first publish. PR #1a's run summary shows current visibility status. |
| Image digest captured in PR #1a is wrong/stale by the time PR #1b lands | PR #1a's run summary is timestamped; PR #1b's author re-runs `gh api repos/<owner>/<repo>/packages/...` or pulls the image and inspects its digest before opening PR #1b to confirm the pin. |
| Cold-cache macOS run exceeds 30min and times out | Cap each job at 45min explicitly. If cold runs exceed 45min, scope down by splitting Brewfile into a CI-only minimal subset (deferred to follow-up). |
| `docker-desktop` cask install fails on hosted runner | Verified via research that install completes (daemon doesn't start). If a future helper invokes `docker ps`, gate on `[[ "${CI:-false}" != "true" ]]` per the chsh pattern. |
| Symlink-resolution assertion fragile if Dotbot's `--verbose` output format changes | Pin Dotbot at v1.24.1 (already vendored as submodule). Bumping the submodule is a separate PR that re-validates the parser. |
| `actions/cache@v4` API change in v5+ | Pin to v4 explicitly. |
| Future Brewfile additions add `mas` entries that fail in CI | Verified absent at plan time; CLAUDE.md note inside install-matrix.yml comment block reminds future authors. |
| Image-tag SHA pin becomes stale (image updated on master, install-matrix still pinned to old digest) | Manual update is the current contract. A separate "rebuild CI image" PR updates the pin. Future automation can round-trip the digest if churn becomes an issue. |
| Fork PR with malicious Brewfile addition runs malicious formula on macos-15 runner | Practical risk low for personal-author repo with single-author write. Documented in install-matrix.yml comment block; tightening via `pull_request_target` + first-time-contributor approval gate is deferred to Open Questions. |

---

## Documentation / Operational Notes

- **PR #1a merge sequence:**
  1. Merge PR #1a to master.
  2. `publish-ci-image.yml` fires automatically (triggered by `paths: ['ci/Dockerfile']`).
  3. Verify the publish run completes; capture the SHA digest from the run summary.
  4. Flip ghcr.io package visibility to public — either manually via the GitHub Packages UI (Settings → Packages → dotfiles-ci-ubuntu → Change visibility), or via a step in the publish workflow that runs `gh api -X PATCH /user/packages/container/dotfiles-ci-ubuntu --field visibility=public`.
  5. Pull the image locally to confirm: `docker pull ghcr.io/<owner>/dotfiles-ci-ubuntu:24.04`.
- **PR #1b open sequence:**
  1. Branch off master (after PR #1a is merged).
  2. Edit `.github/workflows/install-matrix.yml` to pin the image digest (`@sha256:<captured-digest>`).
  3. Edit `install.conf.yaml`'s chsh directive with the CI-env-gate.
  4. Open PR #1b.
  5. CI runs both legs.
  6. Add the seeded-failure validation commit, verify red CI on both legs, capture evidence in `docs/solutions/cross-machine/install-matrix-seeded-failure-evidence-2026-05-03.md`.
  7. Revert the seeded commit; CI returns green.
  8. Merge PR #1b.
- **Brewfile changes will warm the cache key:** any PR touching `brew/Brewfile` OR `helpers/**` busts the macOS cache (per the widened cache-key spec in KTD).
- **First post-PR-#1b PR validates the matrix:** the first non-PR-#1b PR opened after merge will be the first time install-matrix runs on a non-trifecta changeset. Watch its CI output.

---

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-02-compound-engineering-trifecta-requirements.md](../brainstorms/2026-05-02-compound-engineering-trifecta-requirements.md)
- Related code: `.github/workflows/sync-vps.yml`, `install`, `install.conf.yaml`, `install-linux.conf.yaml`, `brew/Brewfile`, `helpers/install_*.sh`, `dotbot/`
- External docs:
  - [GitHub Actions: running jobs in a container](https://docs.github.com/en/actions/using-jobs/running-jobs-in-a-container)
  - [GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
  - [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
  - [actions/cache (v4)](https://github.com/actions/cache)
  - [docker/build-push-action](https://github.com/docker/build-push-action)
  - [Homebrew/actions setup-homebrew workflow](https://github.com/Homebrew/actions/blob/master/.github/workflows/setup-homebrew.yml)
  - [GHCR package visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)
- Related solutions:
  - `docs/solutions/best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md`
  - `docs/solutions/cross-machine/sync-vps-dry-run-previews-current-head.md`
  - `docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md`
  - `docs/solutions/code-quality/zsh-dash-i-c-exit-false-positive-health-check.md`
