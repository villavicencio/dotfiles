---
date: 2026-05-02
topic: compound-engineering-trifecta
---

# Compound-Engineering Trifecta — Hardening + Portability + Surfacing

## Summary

Three sequential PRs that convert `docs/solutions/` from descriptive postmortems into enforced hardening: a cross-platform CI install matrix proves `./install` boots clean on Ubuntu and macOS per PR, a stage-level test harness in `helpers/` lets every postmortem become an executable assertion, and a `/handoff`-triggered index plus curated `critical-patterns.md` surfaces the corpus during review.

---

## Problem Frame

The dotfiles repo invests in compound-engineering postmortems — 25 entries across 5 categories in `docs/solutions/` (`best-practices`, `code-quality`, `cross-machine`, `runtime-errors`, `tmux`), written after every non-trivial bug fix. The investment is real, but the corpus today is descriptive: it explains what went wrong, not why the same shape of bug shouldn't ship again.

Two observations from the recent week make the friction concrete:

1. **PR #55 shipped two pipeline traps that fit existing patterns.** The `read || return 0` short-circuit on EOF-without-newline and the GNU/BSD `stat` divergence both have postmortems that match. Behavioral testing missed them at PR-time; the postmortems didn't catch them either. Bugs shipped, then got new postmortems added next to the old ones.
2. **PR review re-explained the ssh-as-root ownership trap by hand.** That trap is documented in `docs/solutions/cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md`. The doc exists; the reviewer didn't reach for it. Surfacing failed even with `ce-learnings-researcher` auto-recall.

Beyond bug-shipping, the install pipeline itself is currently untested across machines. "Did this PR break fresh-host bootstrap?" gets answered months later when a real machine is wiped — exactly the high-stakes moment the test should run earlier.

---

## Actors

- A1. **Repo author** (single user across personal Mac, work Mac, VPS): edits helpers, ships PRs, runs `./install` on fresh machines, runs `/handoff` between sessions.
- A2. **PR reviewers** (current and future Claude Code agents via `ce-code-review`, `ce-learnings-researcher`): review diffs, cite prior solutions, catch reintroduced traps.
- A3. **GitHub Actions runner** (Ubuntu container + macOS runner): executes the install matrix per PR.

---

## Key Flows

- F1. **CI install matrix on every PR**
  - **Trigger:** PR opened or pushed against master
  - **Actors:** A3
  - **Steps:** Run `./install --dry-run` on Ubuntu container + `macos-15` runner; assert mutation-free dry-run on a fresh `$HOME`. Run `./install` on the same matrix; assert exit zero, no hardcoded `/Users/<user>/` paths in tracked files, expected symlinks resolve, `zsh -i -c true` exits cleanly.
  - **Outcome:** Red CI on broken bootstrap before merge, not after.
  - **Covered by:** R1, R2, R3, R4

- F2. **Helper sibling tests run locally and in CI**
  - **Trigger:** Author runs `./helpers/_test.sh all`, or CI runs the harness as a job
  - **Actors:** A1, A3
  - **Steps:** For each `helpers/install_*.sh`, locate its sibling `*_test.sh` if present; set up fake `$HOME`; mock `brew`/`curl`; run the helper; assert no unexpected mutations; assert specific control-flow branches (dry-run path, error path, idempotent re-run).
  - **Outcome:** Every covered helper has a stage-level safety net; bugs caught at PR-time instead of bootstrap-time.
  - **Covered by:** R5, R6, R7

- F3. **Index regeneration during `/handoff`**
  - **Trigger:** `/handoff` command runs at end-of-session
  - **Actors:** A1 (and the agent executing `/handoff`)
  - **Steps:** As a step before the cadence-log writeback, regenerate `docs/solutions/_index.md` from the current corpus state. If regen fails, log a warning and proceed (non-fatal); cadence-log writeback continues unaffected.
  - **Outcome:** Index never drifts more than one `/handoff` cycle behind reality.
  - **Covered by:** R8, R9

---

## Requirements

**CI install matrix (PR #1)**

- R1. A new GitHub Actions workflow runs the install pipeline on every PR against master, on Ubuntu 24.04 (matches VPS) and `macos-15` (matches personal Mac).
- R2. Both legs run `./install --dry-run` first and assert the dry-run produces zero filesystem mutations on a fresh `$HOME`.
- R3. Both legs then run `./install` and assert: exit zero, no hardcoded `/Users/<user>/` paths in tracked install-pipeline files (`zsh/`, `helpers/`, `brew/`, `git/`), all symlinks declared by the Dotbot config resolve to files inside the repo. The username-agnostic regex `/Users/[^/]+/` is the matcher; documentation under `claude/`, `docs/`, and other intentional references are out of scope.
- R4. Both legs spawn `zsh -i -c true` post-install and assert it exits cleanly — no shell-startup regressions ship through.

**Test harness (PR #2)**

- R5. A `helpers/_test.sh` harness exposes assertion primitives: equality, contains-substring, no-mutation (snapshot-and-compare on a temp `$HOME` using a *portable primitive* — `find -newer` against a sentinel touchfile, not raw `stat -c`/`stat -f` which diverges between GNU and BSD), and exit-code expectation. The harness's *primitives* are bash-3.2-compatible so the harness itself runs on a fresh macOS without a brew dependency. Helpers under test may require newer bash (e.g., `install_omz.sh` uses `declare -A`, which requires bash 4+); the harness invokes them via their declared shebang and assumes the harness operator has installed the helper's required interpreter (e.g., `brew install bash`) before that sibling test runs. Each sibling test declares its bash-version precondition.
- R6. The harness exposes fixture primitives: `with_fake_home` to create a temp `$HOME` and tear it down deterministically; mock primitives for `brew` and `curl` that return canned output without network or disk side effects (PATH-shadowed stubs, the exact mocking shape is a planning detail).
- R7. Initial sibling tests are written for the install helpers covering the install pipeline's most failure-prone surfaces, prioritized by helpers with existing postmortems in `docs/solutions/`: `install_omz`, `install_packages`, `install_node`, `install_nvm`, `install_from_brewfile`. Each `*_test.sh` exercises the helper's dry-run path and at least one critical control-flow branch. Coverage extends to other helpers (`install_fonts`, `install_tmux`, `install_nvim`, etc.) as their failure modes surface — the harness must support that incremental growth without amendment to the harness primitives.

**Solutions index + critical-patterns (PR #3)**

- R8. A regeneration script produces `docs/solutions/_index.md`: a **comprehensive** TOC of all current entries, mirroring the existing 5-folder category structure, with a one-line "what you'd search for" hint per entry derived from frontmatter or first-line heading. The index lists everything in `docs/solutions/`; it is the navigation surface for the full corpus.
- R9. The script is invoked as a step in the existing `/handoff` flow, **after Step 4 (Confirm) and before Step 5 (Forge write-back)** — this position runs uniformly regardless of `forge-project-key:` gating, so the regen step has a stable home in every `/handoff` invocation, including non-Forge repos. Failure to regenerate is **non-fatal but warned** (no-corpus repos warn cleanly and continue); regen must not block `/handoff` or its downstream writebacks.
- R10. **Separately**, `docs/solutions/critical-patterns.md` is a hand-curated short list — a *subset* of the corpus — naming patterns that have bitten ≥2×. Initial set: bash pipeline traps (read-eof + GNU/BSD stat), ssh-as-root ownership trap, dotbot `--dry-run` requires v1.23+, tmux `set-option` bare-index gotcha. (The `find -exec ; vs +` pattern lives as a sub-section of the ssh-as-root postmortem; cross-link there rather than promoting it to its own entry, which would require either backfilling a standalone doc or pointing critical-patterns at a doc fragment.)
- R11. Promotion criterion for `critical-patterns.md`: a pattern qualifies for promotion when it is referenced from 2+ other entries in `docs/solutions/` (cross-link), or referenced in 2+ PR review threads or commit messages. Promotion itself is a manual judgment call, not automated. The two products are distinct: R8's index lists *all* entries, R10's `critical-patterns.md` is the curated subset.

**Cross-cutting (all three PRs)**

- R12. Each PR ships independently and is independently reviewable. The trifecta is a logical unit, but no PR depends on another to merge or function — earlier PRs have value standalone if later PRs slip.

---

## Acceptance Examples

- AE1. **Covers R2.** Given a fresh GitHub Actions runner with no prior `$HOME` state, when `./install --dry-run` runs, then `find $HOME -mindepth 1 | wc -l` returns zero (no mutations).
- AE2. **Covers R3.** Given the install pipeline ran successfully, when the matrix asserts no hardcoded `/Users/<user>/` paths in install-pipeline files, then `git ls-files -- 'zsh/**' 'helpers/**' 'brew/**' 'git/**' | xargs grep -lE '/Users/[^/]+/'` returns no matches. The username-agnostic regex matches any hardcoded user path; tracked documentation under `claude/`, `docs/`, and configuration that legitimately references the install path is intentionally out of scope.
- AE3. **Covers R5, R6.** Given a sibling test for `install_omz`, when the test runs, then the helper executes against a temp `$HOME`, the test asserts the expected `~/.oh-my-zsh` directory exists and the OMZ plugins listed in `zsh/zshrc` are all cloned, and the temp `$HOME` is removed after the test.
- AE4. **Covers R9.** Given the `/handoff` regen step encounters an error parsing a malformed solutions doc, when the regen fails, then `/handoff` logs a warning naming the offending file and continues; the cadence-log writeback proceeds normally.

---

## Success Criteria

- Within 60 days of PR #1 merging, the install matrix red-CIs at least one PR on a bug class with an existing postmortem in `docs/solutions/` (cross-platform divergence, fresh-`$HOME` mutation, or shell-startup regression). PR #1 itself includes a **seeded-failure validation**: a test branch that breaks bootstrap in one of those classes correctly red-CIs on the install matrix before merge, proving the matrix catches the intended bug class without depending on organic bug volume.
- Within 90 days of PR #2 merging, the test harness has at least one sibling test for a *new* helper (one not in R7's initial set) — proves the pattern is sticky, not just initial.
- Within 60 days of PR #3 merging, at least one PR review cites a `critical-patterns.md` entry by URL during review — proves the surfacing layer changes review behavior.
- A future `ce-plan` invocation against any one of these PRs would NOT need to invent: which OS targets, which install commands run, which assertions ran, what success looks like, or which fail-on-PR thresholds apply.

---

## Scope Boundaries

- **Other ideation survivors get their own brainstorms:** mise migration (#1), 1Password `op inject` (#2), per-host Brewfile split (#6), `helpers/bootstrap.sh` (#7).
- **No migration to chezmoi, Nix, or any non-Dotbot ecosystem.**
- **No work-Mac corporate-SSL CI leg.** Would require either a self-hosted runner or careful cert-redaction strategy — separate concern.
- **No deep-behavioral CI assertions** (specific brew package versions, exact command output strings, browser screenshot diffs) — too flaky for cold runners; deferred until the harness exists to host them.
- **No `helpers/doctor.sh` standalone command.** Subsumed by the CI matrix + harness.
- **No automated promotion to `critical-patterns.md`.** Promotion is judgment-driven; `cited-twice` is the prompt to consider promotion, not the trigger.
- **No CLAUDE.md split into agent vs human docs.** Rejected during ideation.
- **No drift-detection daemon or VPS push channel.** Rejected during ideation.
- **No replacement of the bash helpers with TypeScript or Python.** The harness exists precisely so bash stays viable.

---

## Key Decisions

- **Sequential value-first ordering: CI → harness → index.** Ship #1 first because cross-platform install validation pays back immediately, even before any other piece exists. #2 backfills assertions once the matrix is in place. #3 surfaces patterns last, once the harness has proven what counts as critical.
- **`/handoff` is the regen trigger, not pre-commit.** Aligns with the existing cadence ritual; doesn't add per-commit latency; failure mode is non-blocking.
- **CI smoke-level, not deep-behavioral.** Deep assertions on a cold runner are flaky; smoke level (mutation-free dry-run, exit zero, paths sane, shell starts) catches the bug class actually at risk without flake noise.
- **Bash 3.2 is the harness baseline.** macOS ships with bash 3.2 by default; assuming bash 5+ would force a brew dependency just to run tests locally on a fresh Mac.
- **Three separate PRs, not one unified PR.** Each PR is small enough to review well; the three reinforce each other without any one blocking another. R12 codifies independence.
- **PR labeling and issue cadence.** Each PR is linked to a separate GitHub issue, labeled `compound-engineering` so the trio is greppable as a coherent landing. Issues open at the start of each PR's work, not upfront for all three — this is project-management convention, not a functional requirement of the work.

---

## Dependencies / Assumptions

- Existing `Dockerfile` at the repo root is **structurally unusable** for the Ubuntu CI leg — it targets `ubuntu:20.04` (PR #1 needs 24.04), creates a `tester` user with sudo (the VPS install runbook expects root, and `install-linux.conf.yaml` assumes root), and pre-installs only minimal bootstrap deps (`zsh python3 git sudo curl`). PR #1's scope explicitly includes rewriting the Dockerfile from scratch: `ubuntu:24.04` base, root user (matching VPS reality), and only the bootstrap deps that `helpers/install_packages.sh` does not install itself.
- `macos-15` GitHub Actions runner is available on the user's plan and within minute budget for per-PR runs.
- Existing `/handoff` skill in `claude/commands/handoff.md` exposes a clean insertion point for the regen step before the cadence-log writeback (verified at brainstorm time).
- 1Password CLI / `op inject` is **not** a dependency of this trifecta — that's a sibling brainstorm; this work runs without it.
- `ce-learnings-researcher` continues to auto-recall solutions docs; this work adds a complementary surfacing layer, not a replacement.

---

## Outstanding Questions

### Resolve Before Planning

(none — all scope-shaping questions resolved)

### Deferred to Planning

- [Affects R1][Technical] What does the macOS leg actually run? Does `brew bundle` work cleanly on a fresh `macos-15` runner without auth or signed-in iCloud, and how should runner cache hits be handled?
- [Affects R6][Technical] Exact mocking shape for `brew`/`curl` — `PATH`-shadowed stub scripts in a temp dir, environment overrides like `BREW_BIN`, or function shadowing in the harness shell. R5's no-mutation assertion now uses a `find -newer` portable primitive (independent of the mocking shape), so this is a planning-time technical decision rather than a brainstorm-shaping blocker.
- [Affects R8][Needs research] What metadata drives the "what you'd search for" hint per entry — frontmatter field, first-line heading, or a hand-written 1-line description per doc.

## Deferred / Open Questions

### From 2026-05-02 review

The following findings surfaced in `ce-doc-review` and were deferred for `ce-plan` to resolve. Each entry names the affected requirement(s), the finding's nature, and the tradeoff to weigh.

- **[Affects R1, R3][P1 / macOS budget vs smoke framing]** Brewfile has 95 formulas + 3 casks (docker-desktop ~1GB); cold `macos-15` runner runs 20-30min per PR at 10× Linux minute cost. This contradicts the "smoke-level" framing. Tradeoff: pin smoke Brewfile subset for the macOS leg, skip `brew bundle` entirely there (validate via dry-run + symlinks + `zsh` startup only), use brew-cache GitHub Action, or cadence the macOS leg to weekly instead of per-PR. (feasibility, adversarial)
- **[Affects Success Criteria #4 / Deferred-to-Planning list]** SC#4 claims "no invention needed" but the deferred list still has substantive open questions (macOS leg specifics, index metadata source). Tradeoff: resolve the remaining DQs before merging the brainstorm, or rephrase SC#4 as "no invention needed beyond the Deferred-to-Planning items." (adversarial)
- **[Affects R4][P2 / scope alignment]** R4 (`zsh -i -c true` startup smoke) is install-pipeline hygiene rather than an enforcement of any specific postmortem — has no goal parent in the trifecta's stated bet. Tradeoff: cut R4 from the trifecta and add it as a standalone enhancement to a future PR, or add a one-line justification in Problem Frame tying shell-startup regressions to the postmortem corpus. (scope-guardian)
- **[Affects Summary][P2 / bet framing]** The Summary stakes the trifecta on "convert docs/solutions/ from descriptive to enforced." PR #1 (cross-platform install matrix) does not fit that frame cleanly — it tests fresh-host bootstrap, not postmortem-becomes-assertion. Tradeoff: split the bet into "(1) cross-platform install untested" + "(2) postmortems descriptive→enforced," or accept the looser frame. (product-lens)
- **[Affects R5, R6][P2 / harness vs library]** R5/R6 specify a non-trivial bespoke bash testing framework (assertion primitives, fixture primitives, mocking shape, bash-3.2 compatibility). bats-core, shellspec, and shunit2 cover the same shape. Tradeoff: adopt a third-party framework (less long-term maintenance for a 1-person team), hand-roll only the missing pieces, or commit to the bespoke `_test.sh`. (product-lens)
- **[Affects R3][P2 / smoke floor coverage]** Mutation-free + exit-zero + path-sane + `zsh -i -c true` passes 3 plausible bug classes: helpers mutating outside `$HOME` (e.g., `/tmp`, `/usr/local`), interactive widget breakage that `-c true` doesn't exercise, and symlinks resolving to wrong targets. Tradeoff: scope the smoke claim explicitly ("catches bootstrap-syntax-breakage class only") or expand R3 with system-wide mutation check, an interactive-shell smoke (`zsh -i -c 'compdef -d 2>&1'`), and symlink target verification. (adversarial)
- **[Affects R6][P2 / mock isolation]** PATH-shadowed mocks are bypassed by helpers using `command curl`, `/usr/bin/curl`, absolute paths, or `PATH=` resets. The mock no-network promise is silently violated and tests report green. Tradeoff: add a lint rule prohibiting bare-binary-bypass patterns, layer defense by exporting `http_proxy=http://127.0.0.1:1` so a circumvented mock fails loudly, or accept the limitation. (adversarial)
- **[Affects R9][P2 / regen drift failsafe]** Non-fatal regen failure is logged once and easily missed; subsequent sessions consume a stale `_index.md` until a manual run repairs it. Tradeoff: write a sentinel file (`docs/solutions/.index-last-success`) that `/pickup` reads and surfaces if older than N sessions, write a regen-failed banner into `_index.md` itself, or accept silent staleness. (adversarial)
- **[Affects R11][P2 / promotion failsafe]** Cited-twice (cross-link OR PR thread OR commit message) is unlikely to fire when reviewers paraphrase rather than link, when commit messages describe fixes rather than cite patterns, or when back-edits to old postmortems are rare. Tradeoff: add a quarterly audit step (grep new postmortems for shape-matches against existing entries), relax the criterion to "second postmortem of similar shape" regardless of citation, or accept that the criterion is aspirational. (adversarial)
- **[Affects R1, R3 / Dependencies][P2 / macOS cask auth]** Brewfile casks (`docker-desktop`, `git-credential-manager`, `corelocationcli`) may require interactive auth or iCloud sign-in on a fresh runner. Tradeoff: split Brewfile to exclude casks from the CI leg, document the constraint as a hard dependency, or use a pre-warmed runner image. (coherence)
- **[Affects R5, R6][P2 / harness primitives scope]** R5 + R6 declare 7 primitives (`assert_eq`, `assert_contains`, no-mutation, exit-code, `with_fake_home`, `mock_brew`, `mock_curl`) for 5 initial sibling tests. `mock_brew`/`mock_curl` are needed for live-branch tests, but R7 only commits to "at least one critical control-flow branch" — underspecified. Tradeoff: defer `mock_brew`/`mock_curl` to a later planning decision (only build when a confirmed consumer exists), or commit them as required primitives now. (scope-guardian)
- **[Affects Success Criteria #2, R5, R6][P2 / extensibility]** SC#2 says "within 90 days a sibling test for a *new* helper" — which implicitly requires the harness to be addable-to without harness-source amendment. R5/R6 don't state that. Tradeoff: add an explicit extensibility requirement to R5/R6 ("a new `*_test.sh` file is sufficient — `_test.sh` itself does not need editing"), or reframe SC#2 as aspirational rather than verifiable. (scope-guardian)
- **[Affects Key Flows F2 vs R1-R4][P3 / CI invocation ordering]** F2 says "CI runs the harness as a job" but R1-R4 (PR #1 scope) do not include a harness step. If PR #1 implementer adds `./helpers/_test.sh` to the workflow, CI fails because the file doesn't exist yet (R12 independence broken). Tradeoff: add an R7a stating that PR #2 amends the workflow from PR #1 to invoke the harness, or delete the "or CI runs the harness as a job" clause from F2 and treat harness-in-CI as separate later work. (adversarial)
