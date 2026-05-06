---
date: 2026-05-02
topic: dotfiles-improvements
focus: open-ended ideation on improvements to a personal multi-machine dotfiles repo
mode: repo-grounded
---

# Ideation: Dotfiles Improvements

ce-ideate run `2fb768d6`. 6-frame default dispatch (pain, inversion, assumption-breaking, leverage, cross-domain, constraint-flipping). 25 deduped master candidates → 7 survivors after adversarial filtering.

## Grounding Context (Codebase)

Personal multi-machine dotfiles for 2 Macs + 1 Ubuntu VPS managed via Dotbot v1.24.1. ~25 config dirs, 11 install helpers in `helpers/`, mature CLAUDE.md (269 lines) documenting all conventions.

**Architecture pillars:**
- Lazy-loader pattern for NVM/pyenv/FZF (200-400ms startup savings — current invariant)
- XDG compliance, dual-arch via `$BREW_PREFIX`
- Machine-specific overrides via untracked files (`~/env.sh`, `~/.gitconfig.local`, `~/.ssh/config`)
- VPS sync via GH Actions `sync-vps.yml` (Tailscale tag:gh-actions → tag:prod, OAuth, Dotbot --dry-run preview)
- Forge SSH bridge to OpenClaw VPS for `/pickup` inbox archive + `/handoff` cadence-log writebacks
- 23+ entries in `docs/solutions/` (compound-learning corpus auto-recalled by `ce-learnings-researcher`)

**Pain surface (from scan):**
1. README is stale boilerplate — no entry point for 3-machine setup, Dotbot, dry-run, VPS runbook
2. 11 install helpers with duplicated `DOTFILES_DRY_RUN` guards, no shared library
3. Sequential helper execution (no parallelism for independent steps)
4. VPS setup buried in `docs/solutions/` only
5. No post-install audit (broken symlinks, drift go undetected)
6. OMZ plugin sync manual (zshrc `plugins=()` ↔ `install_omz.sh` drift possible)
7. Single `Brewfile` for all 3 hosts (work Mac corporate-tools split, VPS Linux split unmodelled)
8. Untested install pipeline — every machine bootstrap is the test

**Past learnings shaping ideation:**
Bash pipeline traps shipped twice this week (`docs/solutions/best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md`). PR #55 reviewers re-explained the ssh-as-root ownership trap that's already documented. Verify-with-runtime-data over docs/subagent claims. Hooks need `</dev/null >/dev/null 2>&1`. PUA glyphs strip via Bash/Write/Edit.

**External landscape:**
mise (Rust, ~10-30ms init) replaces NVM+pyenv+rbenv stack — eliminates lazy-loader use case entirely. chezmoi has run_once_ + per-machine templates. 1Password `op inject` for zero-disk-exposure secrets. Atuin self-hostable. `just` task runner for discoverability. ashishb/dotfiles tests via GH Actions Docker+macOS install matrix. Community consensus: Nix is over-engineering for dotfiles per se; mise + per-project devbox/devenv is the sweet spot.

## Ranked Ideas

### 1. Migrate runtime managers to `mise` — delete the lazy-loader era
**Description:** Replace NVM/pyenv/RVM lazy loaders with mise (Rust). Deletes `_load_X` shim pattern, npm-globals shim list, `command <tool>` recursion footgun, ~40 lines of CLAUDE.md.
**Warrant:** **direct:** CLAUDE.md "Lazy loader pattern" — *"Direct sourcing of NVM alone adds 200-400ms to shell startup."* That justification dissolves under mise. **external:** mise <30ms init benchmarks. **reasoned:** every shim line you delete is a future not-written.
**Rationale:** 5/6 ideation frames converged on this — strongest signal. Removes a recurring tax (every new npm-global needs a shim).
**Downsides:** Real migration cost across zshrc/zshenv/install_node/install_nvm/Brewfile. mise's `.tool-versions` convention is its own learning curve. Some asdf plugins have edge cases.
**Confidence:** 80%
**Complexity:** Medium
**Status:** Unexplored

### 2. 1Password `op inject` for `~/env.sh` and machine overrides
**Description:** Versioned `templates/env.sh.tpl` with `{{ op://Vault/Item/field }}` references; new `helpers/install_env.sh` runs `op inject` per machine. Vertex AI service-account JSON moves from `~/Downloads/` into 1Password.
**Warrant:** **direct:** CLAUDE.md "Setting up the work Mac" step 6 prescribes `GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/...json` — same doc's "Common offenders" flags `~/Downloads/` paths as anti-pattern. **external:** `op inject` is the canonical zero-disk-exposure pattern.
**Rationale:** Work Mac is corporate-managed; if MDM moves Downloads, every Claude Code session breaks. Centralizes secret rotation.
**Downsides:** Adds `op` as startup-path dependency (latency, "is op signed in?" prompts). Service-account auth on VPS needs separate setup.
**Confidence:** 85%
**Complexity:** Medium
**Status:** Unexplored

### 3. CI install matrix — every PR bootstraps a fresh box
**Description:** `.github/workflows/install-matrix.yml` running `./install --dry-run` then `./install` on Ubuntu container + macos-15 GH runner per PR. Asserts exit 0, no hardcoded paths, fresh-host dry-run produces zero filesystem mutations, shell-startup under budget.
**Warrant:** **direct:** Only `sync-vps.yml` exists; CLAUDE.md names "Untested install pipeline — every machine bootstrap is the test" as recurring friction. Dockerfile already exists at repo root. **external:** ashishb/dotfiles publishes exactly this pattern.
**Rationale:** Shifts the failure window from "machine wipe day" to "PR review."
**Downsides:** macOS runner minutes are pricier (~10× Linux). Cold install runs are slow (Brewfile 5-10 min). Mitigations: macos-15 only on PRs touching brew/ or helpers/.
**Confidence:** 88%
**Complexity:** Medium
**Status:** Explored (selected 2026-05-02 as part of CC-1 trifecta brainstorm seed)

### 4. `helpers/_test.sh` — stage-level test harness for helpers
**Description:** Bash test harness exposing `assert_eq`, `assert_no_mutations`, `with_fake_home`, `mock_brew`. Each helper gets a sibling `*_test.sh`. `./helpers/_test.sh all` runs all locally; CI wires it as a job.
**Warrant:** **direct:** PR #55 shipped two pipeline traps in one week (read-eof, GNU/BSD stat) — both documented in `docs/solutions/best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md`. Stage-level testing would have caught both. The dotbot dry-run audit pattern in CLAUDE.md (`find "$FAKE" -mindepth 1 | wc -l   # must be 0`) already encodes the no-mutation primitive.
**Rationale:** Bug rate ≥2/week. Detection latency is the bottleneck. Once the harness exists, every future helper is ~5 lines of test.
**Downsides:** Mocking shell tools cleanly is awkward. Bash 3.2 on macOS limits the API. Tests rot if helpers refactor and tests don't.
**Confidence:** 75%
**Complexity:** Medium
**Status:** Explored (selected 2026-05-02 as part of CC-1 trifecta brainstorm seed)

### 5. `docs/solutions/_index.md` + `critical-patterns.md`
**Description:** Auto-generated `_index.md` (table of contents grouped by category with one-line search hints) and `critical-patterns.md` (the 5-7 patterns where wrong-default-behavior has bitten ≥2×). Regenerated by a small script triggered from `/handoff` or pre-commit.
**Warrant:** **direct:** PR #55 reviewers re-explained the ssh-as-root trap already documented in `docs/solutions/cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md` — surfacing failed even with auto-recall. **reasoned:** knowledge that exists but isn't surfaced has worse second-order effects than knowledge that doesn't exist.
**Rationale:** Lowest-cost survivor. ce-code-review can cite stable URLs; "cited-twice → promotes to critical-patterns" makes the corpus self-curate.
**Downsides:** Index regen script is one more thing to maintain. Promotion criteria need judgment.
**Confidence:** 90%
**Complexity:** Low
**Status:** Explored (selected 2026-05-02 as part of CC-1 trifecta brainstorm seed)

### 6. Per-host Brewfile split
**Description:** `Brewfile.common` + `Brewfile.{personal,work,vps}`, dispatcher in helper. Hostname pattern, `MACHINE_PROFILE` env, or `~/.dotfiles-profile` sentinel selects which fragments to apply.
**Warrant:** **direct:** Single 99-package Brewfile; CLAUDE.md enumerates work-only env vars but no work-only packages. Personal-Mac brews get attempted on work Mac on next bundle. **external:** chezmoi templating, `brew bundle dump diff`.
**Rationale:** Forces a decision at add-time; makes "what does work have that I don't" answerable via `diff`.
**Downsides:** 3 fragments to maintain. Adding a package now requires "which fragment" thought.
**Confidence:** 80%
**Complexity:** Low-Medium
**Status:** Unexplored

### 7. `helpers/bootstrap.sh` — runbook becomes script
**Description:** `./bootstrap --profile {personal,work,vps}` detects host, runs the right `./install` config, renders per-machine files via `op inject` (#2), applies the right Brewfile fragment (#6), prints remaining manual steps (1Password unlock, GH SSH key, TCC grant). CLAUDE.md "Setting up the work Mac" 8-step prose collapses to one command.
**Warrant:** **direct:** CLAUDE.md "Setting up the work Mac" is an 8-step manual checklist. **reasoned:** prose runbooks decay because the cost of keeping them in sync with reality is higher than the cost of using them stale; bash scripts are exercised every time someone uses them, so they can't silently lie.
**Rationale:** Work-Mac rebuild today is 30-60 min. Profile bootstrap compresses to one command + 1Password unlock.
**Downsides:** Profile detection adds complexity. Depends on #2 and #6 to be fully realized.
**Confidence:** 78%
**Complexity:** Medium
**Status:** Unexplored

## Cross-cutting Clusters

- **CC-1: Compound-engineering trifecta = #3 + #4 + #5.** Together convert docs/solutions/ from descriptive to enforced — every bug gets a doc + an executable assertion + a stable surface + auto-recall. **Selected as brainstorm seed 2026-05-02.**
- **CC-2: Bootstrap-experience overhaul = #7 + #2 + #6.** Compresses work-Mac rebuild from "8 prose steps" to "one command + 1Password unlock." Best after CC-1 lands so test scaffolding makes the migration safer.
- **CC-3: #1 standalone.** Largest single deletion of CLAUDE.md surface; clean break from "this pattern was load-bearing in 2022."

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| G | OMZ plugin single-source | Below ambition floor relative to top-7; pattern captured at higher altitude in CC-1. |
| H | `helpers/doctor.sh` standalone | Subsumed by #3 (CI matrix asserts the same invariants per PR) and #4 (test harness). |
| I | `just` task runner | Lower leverage than top-7; better as a /ticket if discoverability friction surfaces concretely. |
| J | Atuin self-hosted on VPS | Real value but offset by secret-leakage risk in command lines (mitigations need careful setup). |
| K | Brewfile drift detection (CI dump diff) | Duplicates #3 + #6 once landed. Drift detection is a feature of the CI matrix. |
| L | Push→pull VPS sync (systemd timer) | Too expensive: existing sync-vps.yml is fresh and validated; asymmetry doesn't outweigh disruption. |
| M | Genome-VCF per-machine variant file | Reasoned-only warrant; novel data structure but uncertain ROI at 3 machines. |
| N | Aircraft checklist + abort tiers + rollback | Too expensive: rollback infra is heavy for helpers that don't fail catastrophically. |
| O | Symphony orchestra parts — role-scoped configs | Duplicates #6 + #7. |
| P | Hospital sentinel events — drift taxonomy | Duplicates #5. The taxonomy is the index. |
| Q | CIP catalog — per-dir intent metadata | Too expensive: maintenance overhead per dir without immediate concrete benefit. |
| R | Toyota Andon cord — push-channel drift | Subsumed by CC-1 once test harness + CI matrix are in place. |
| S | Sourdough starter lineage — per-host divergence log | Duplicates M (already rejected). |
| T | Benedictine Rule — codified maintenance cadence | Too vague: concrete cadences belong in `/schedule` offers, not a meta-document. |
| U | CLAUDE.md split — agent prompt vs human docs | Counter-argument: CLAUDE.md is auto-loaded by harness; conflating audiences may be the right design for an LLM-collaborative repo. |
| W | Replace `/etc/hosts` GitHub IPs with DNS-layer fix | Below ambition floor — narrow work-Mac-only fix. Better as a /ticket if it bites. |
| X | Tier some helpers out of bash (TS/Python) | Duplicates #4's value with worse trade-off (cognitive load of another language). |
| Y | Reframe Forge: dotfiles IS a Forge project | Too vague — concrete moves are individually represented and individually rejected. |
