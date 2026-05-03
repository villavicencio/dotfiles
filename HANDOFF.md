# HANDOFF — 2026-05-03 (PDT, late afternoon)

Long single session that crossed 2026-05-02 → 2026-05-03. Started with `/pickup` housekeeping (committing symlink-driven docs, fixing topgrade noise), then ran a full compound-engineering pipeline on a substantive feature: `/ce-ideate` → `/ce-brainstorm` → `/ce-doc-review` → `/ce-plan` → `/ce-doc-review` → `/ce-work` → `/ce-code-review` → 2× walkthrough fixes. Net result: **PR #56 merged** (CE trifecta PR #1a), image live and public on ghcr.io, digest captured for PR #1b.

## What We Built

### PR #56 — feat(ci): CI Dockerfile + publish-ci-image workflow (squash-merged 2026-05-03T20:55Z as `9c7715a`)

The full per-commit history is preserved in PR #56's "Commits" tab; the squash collapses to one master commit:

- `ci/Dockerfile` — minimal `ubuntu:24.04@sha256:c4a8d550...` (manifest-list digest), root user, only the bootstrap deps `helpers/install_packages.sh` does NOT install itself: `ca-certificates`, `curl`, `git`, `zsh`. `sudo` intentionally NOT installed — comment block calls out the no-USER design.
- `.github/workflows/publish-ci-image.yml` — publishes `ci/Dockerfile` to `ghcr.io/${{ github.repository_owner }}/dotfiles-ci-ubuntu:24.04` on master pushes touching `ci/Dockerfile` OR the workflow file itself; plus `workflow_dispatch`. **All 4 third-party actions are SHA-pinned** (`actions/checkout@34e114876b...`, `docker/login-action@c94ce9fb46...`, `docker/setup-buildx-action@8d2750c68a...`, `docker/build-push-action@10e90e3645...`). Idempotent visibility auto-flip step (`gh api -X PATCH .../visibility -f visibility=public`) with `/user/` → `/orgs/<owner>/packages/...` fallback warning. Empty-digest validation (regex `^sha256:[0-9a-f]{64}$`, fail loudly). Concurrency `cancel-in-progress: true` (latest-wins for image publishers). `outputs: digest:` on the job (cross-job output; see Gotchas for the external-query caveat).
- Repo-root `Dockerfile` (Sep 2024, `ubuntu:20.04` + `tester` user, verified unused) — deleted.
- `docs/ideation/2026-05-02-dotfiles-improvements-ideation.md` (132 lines) — 25 candidates → 7 survivors with rejection reasons. CC-1 selected (compound-engineering trifecta).
- `docs/brainstorms/2026-05-02-compound-engineering-trifecta-requirements.md` (171 lines) — trifecta requirements; 13 deferred questions from review pass appended in `## Deferred / Open Questions`.
- `docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md` (387 lines) — PR-split into PR #1a (this PR) + PR #1b (install-matrix), with the chicken-and-egg sequencing decision documented in Key Decisions. 3 Resolve-Before-Implementation items remain for PR #1b.
- `CLAUDE.md` Structure table — `docs/{brainstorms,ideation,plans}/` and `ci/` now present.

PR #56 is closed; the `feat/ci-image-publish` branch is deleted both locally and on origin.

### Earlier in this session — 4 direct-to-master commits (2026-05-02, before PR #56)

- `e846d51` docs(claude) — `claude/CLAUDE.md` symlink-target additions: **Personal Boundaries policy** (don't tell user when to sleep/eat/rest) + Proof naming convention + Proof API limitations.
- `b464b67` feat(pickup) — `claude/commands/pickup.md` symlink-target additions: HANDOFF_STALENESS probe + uptime + ssh brute-force pressure + fail2ban jail status (in Step 2d, only fires for `forge-project-key=openclaw-forge` projects).
- `6012c5a` chore(topgrade) — silenced pnpm + containers steps in `topgrade/topgrade.toml` (with explanatory comments).
- `b2169b0` chore(topgrade) — silenced microsoft_office step in same file.

### Local-only environment changes (not in any commit)

- `pipx uninstall uv` — removed redundant pipx-installed uv (was failing with stale Python interpreter; `~/.local/bin/uv` standalone install handles updates via topgrade's `uv` step).
- `~/package.json` — added `"private": true` (silences yarn's "no license field" warning on every yarn invocation).
- `~/package-lock.json` — deleted (yarn-pinned package.json conflicted with leftover npm lockfile; explicit yarn warning told us to remove it).

### Image state (ghcr.io)

- Published: `ghcr.io/villavicencio/dotfiles-ci-ubuntu:24.04`
- **Digest for PR #1b pinning: `sha256:8b0b7108e32229d7842c7cb876bc7f322f114e079d171d9725d1e71279dd3865`**
- Visibility: **public** (auto-flip step worked on first run; verified via `curl ghcr.io/v2/...` returning HTTP 200 with anon token)
- Workflow run: `25290561325` succeeded in 43s on the merge commit (auto-fired due to paths filter on `ci/Dockerfile`)
- Anonymous-pullable: confirmed via registry HTTP API (local `docker pull` was unavailable because Docker Desktop daemon isn't running; image itself is fine)

## Decisions Made

- **PR-split for the CE trifecta PR #1.** Originally a single PR; ce-doc-review (4 reviewers converged on this as P0) flagged that `publish-ci-image.yml` triggers on `push: branches: [master]` only — fires post-merge, not on pull_request. So PR #1a's own install-matrix CI couldn't pull a not-yet-published image. Split into PR #1a (ci/Dockerfile + publish workflow) + PR #1b (install-matrix + install.conf.yaml chsh CI-gate + comment block). Each is independently mergeable.
- **SHA-pin third-party actions in PR #1a.** Originally deferred; ce-code-review surfaced supply-chain risk; resolved live via `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`. No dependabot config yet — manual SHA updates are the cost; dependabot can land in a follow-up if maintenance burden surfaces.
- **SHA-pin ubuntu base in ci/Dockerfile.** Same supply-chain principle. Resolved live via Docker Hub registry API (manifest-list digest, multi-arch). Closes the asymmetry where the published image was digest-pinned but its build input was a mutable `:24.04` tag.
- **Visibility auto-flip step in publish workflow.** ce-code-review found "first-publish private by default" was a human-in-the-loop step that broke agent automation. Replaced with idempotent `gh api` step that fails gracefully (warns) and retries on next run.
- **Concurrency `cancel-in-progress: true` for the publisher.** Originally `false` (mirroring `sync-vps.yml`); ce-code-review flagged that latest-wins is correct for image publishers — orphan layers GC-cleared by ghcr.io.
- **Sequential value-first ordering for the trifecta** (CI matrix → harness → solutions index). Confirmed during ce-brainstorm.
- **`/handoff` is the regen trigger for `docs/solutions/_index.md`** (not pre-commit) — confirmed during ce-brainstorm. Specified as "after Step 4, before Step 5" in PR #1b's plan so it runs uniformly regardless of `forge-project-key:` gating.
- **CI smoke-level relabeled to "scoped CI assertions"** in the plan after ce-doc-review flagged that 5 assertions exceeded "smoke."
- **Bash 3.2 baseline for the harness primitives** (PR #2). Helpers under test may require newer bash; the harness invokes them via shebang and assumes the operator has the right interpreter.
- **Manual seeded-failure validation discipline** (not workflow code). PR #1b includes a temp commit that breaks bootstrap, CI red-CIs, log-inspect → revert before merge. Origin Success Criterion #1.
- **Best-judgment routing for the doc/code reviews** given session length. ce-doc-review on the brainstorm (24 findings), the plan (15 findings), and the PR code (14 findings) all used the auto-resolve path; the agent-fixer pattern handled the bulk efficiently.
- **Auto-mode honored throughout.** ~50+ tool calls without unnecessary interruptions; questions only fired at genuine decision points.

## What Didn't Work

- **Single-PR plan for the trifecta PR #1.** Quietly assumed publishers and consumers could ship together; ce-doc-review's chicken-and-egg P0 forced the split. Lesson: when a workflow consumes another workflow's output, sequence the publisher first.
- **`gh run view --json jobs --jq '.jobs[].outputs.digest'`** as the programmatic capture path for PR #1b. Job-level `outputs:` blocks are only visible to downstream jobs **within the same workflow run** — they're NOT exposed via `gh run view` after the fact. Use the registry HTTP API instead (worked: returned `docker-content-digest` header). Documented in Gotchas; F4's "programmatic capture" benefit is narrower than billed.
- **`docker pull ghcr.io/...`** locally — Docker Desktop daemon isn't running, so the command fails with a "no such socket" error. The image is fine; the failure is purely local tooling. Use the registry HTTP API or `skopeo inspect` (no daemon needed) for verification.
- **ce-learnings-researcher dispatch in PR #56's code review** was missed — my dispatcher mistakenly assigned `ce-security-reviewer` to that slot instead. 8 of 9 planned reviewers ran. Past-learnings coverage gap noted in Coverage; not blocking, but worth flagging if running ce-code-review against more code in the future.
- **Tier 1 inline self-review** considered for PR #56 (purely additive, single concern, pattern-following). Rejected: deleting the old Dockerfile was technically a behavior change, even if verified unused. Used Tier 2 ce-code-review instead — surfaced 14 findings, all addressed before merge.
- **Top-of-Dockerfile TODO comment** for ubuntu base SHA pin (left in commit `86863ec`, removed in commit `8dca13a` after walkthrough applied the actual pin). The TODO was an honest "I can't fetch the SHA from this session" punt; the walkthrough resolved it via Docker Hub registry API.

## What's Next

1. **PR #1b — `feat/ci-install-matrix`** (or whatever branch name you prefer). Implements U3 + U4 from the plan:
   - `.github/workflows/install-matrix.yml` with two jobs (`linux:` + `macos:`) — `linux:` references the digest-pinned image: `ghcr.io/villavicencio/dotfiles-ci-ubuntu@sha256:8b0b7108e32229d7842c7cb876bc7f322f114e079d171d9725d1e71279dd3865`
   - `install.conf.yaml` — gate the chsh shell directive on `[[ "${CI:-false}" != "true" ]]` so CI doesn't trip on chsh PAM auth
   - Inline architectural-caveats comment block at the top of `install-matrix.yml`
   - Seeded-failure validation (manual: temp commit on the PR branch that breaks bootstrap → CI red on both legs → revert → merge)
2. **Resolve the 3 RBI items in PR #1b at open time** — fork-PR trust boundary (tighten via `pull_request_target` + first-time-contributor approval, OR document and accept), credential-pattern detection in R3 (gitleaks vs accept gap), inline architectural-caveats comment block scope.
3. **Image refresh cadence**: when Canonical patches `ubuntu:24.04` or any of the 4 SHA-pinned actions ships a fix worth picking up, manually update the SHA pins. Tracked as a follow-up; may eventually want a github-actions dependabot config but not blocking.

## Gotchas & Watch-outs

- **Image SHA `sha256:8b0b7108e32229d7842c7cb876bc7f322f114e079d171d9725d1e71279dd3865`** is the value PR #1b's install-matrix.yml needs to pin. If you re-publish the image (touch `ci/Dockerfile` on master OR `workflow_dispatch`), the digest changes; refresh from the registry HTTP API (the `docker-content-digest` header on `GET /v2/villavicencio/dotfiles-ci-ubuntu/manifests/24.04`).
- **`gh run view --json jobs` does NOT expose job-level `outputs:` for external queryers** — those outputs are for cross-job within the same workflow run. The "programmatic capture" benefit of F4 is narrower than billed. For external queryers, use the registry HTTP API. Worth a one-line clarification in PR #1b's Operational Notes.
- **Docker Desktop daemon must be running** for `docker pull` / `docker buildx imagetools inspect` etc. We disabled it from topgrade earlier this session (it was failing because the daemon isn't auto-started). If you want a daemon-free path: `skopeo inspect docker://ghcr.io/villavicencio/dotfiles-ci-ubuntu:24.04` (after `brew install skopeo`) OR raw `curl https://ghcr.io/v2/...` with the anon token from `https://ghcr.io/token`.
- **The publish-ci-image workflow's `paths:` filter now includes the workflow file itself** (one of the ce-code-review fixes). Editing the workflow on master will republish the image — intended behavior, but means action-version bumps or new steps will burn a fresh digest.
- **Visibility auto-flip is best-effort.** If `secrets.GITHUB_TOKEN` lacks `admin:packages`, the step prints a `::warning::` and the workflow still succeeds. Manual flip via Settings → Packages is the fallback.
- **3 Resolve-Before-Implementation items in the plan** affect PR #1b only. They're documented in `docs/plans/2026-05-03-001-feat-ci-install-matrix-plan.md` under Outstanding Questions → Resolve Before Implementation.
- **Squash-merge collapsed PR #56's 5 commits into one master commit** (`9c7715a`). Per-commit history is preserved in PR #56's "Commits" tab if you ever need to spelunk.
- **Carry-forward from earlier sessions:** `claude/CLAUDE.md` and `claude/commands/pickup.md` are symlinked into `~/.claude/`; edits made through the live Claude UI write back through to the repo. Earlier this session we committed those (commits `e846d51` + `b464b67`); future sessions should treat any `M` on those files as real edits, not "leave alone" noise (memory entry exists at `feedback_claude_symlink_writeback.md`).
- **`/handoff` Step 5 + 6** runs the Forge bridge if `forge-project-key:` is set. This repo has `forge-project-key: dotfiles` so the cadence-log + shared/comms appends will fire on this run. Trailing `chown 1000:1000` is the invariant for ssh-as-root writes per dotfiles#47/#50.
