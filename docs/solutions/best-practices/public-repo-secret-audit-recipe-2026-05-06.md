---
title: "Public-repo secret-audit recipe + force-push-to-amend when a PR commit carries unredacted secrets"
date: 2026-05-06
category: best-practices
tags:
  - secret-audit
  - public-repo
  - trufflehog
  - opsec
  - force-push-amend
  - defense-in-depth
  - pre-commit
  - github-pat
severity: high
component: tooling
problem_type: best_practice
module: security-audit-workflow
applies_when:
  - "Auditing a public git repo (dotfiles, shell-config, anything with shell-style env exports) for leaked credentials, especially with pre-2021 history that may contain legacy 40-hex GitHub PATs"
  - "A trufflehog or gitleaks scan returns zero or few findings on a long-history repo and you need to decide whether to trust that as a complete count"
  - "An open PR commit contains unredacted secret values (even if the underlying credential is dead) and HEAD must not ship those values to master"
  - "Migrating a long-history repo from private to public, or doing a periodic 'is anything bleeding from this repo' check"
related_solutions:
  - "docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md — concrete worked example this recipe was distilled from; contains the trufflehog v3.95.2 keyword-gated detector source citations and the specific PAT fingerprints"
  - "docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md — sibling postmortem that got OPSEC trim in the same PR; demonstrates why Step 4's docs-inclusive scan matters (six employer-identifying occurrences in this file alone)"
---

# Public-repo secret-audit recipe + force-push-to-amend when a PR commit carries unredacted secrets

## Context

A scanner-only secret audit on a long-history public repo produces a confidently-wrong "all clear" when the scanner's blind spots align with the repo's actual leak shape. Trufflehog v3.95.2's legacy 40-hex GitHub PAT detector is keyword-gated by variable-name prefix, so tokens stored under env vars without a GitHub-flavored substring are invisible. `Verified: false` is routinely misread as `revoked` when it can also mean "scanner probed an out-of-scope endpoint." OPSEC scans that exclude `docs/` carve out exactly the directories where a written postmortem may itself contain the leaked value. And when a leak IS found in an open PR commit, the additive-fixup-commit instinct leaves the bad blob in branch history reachable via direct-SHA URLs even after squash-merge.

This recipe captures the paired-tool audit procedure that catches what scanner-alone misses, plus the force-push-to-amend workflow that prevents in-flight PRs from carrying secrets into branch history.

## Guidance

### The 7-step audit

**Step 1 — Trufflehog filesystem + git scans.** Cheap, fast, exhaustive on modern prefixed tokens (`ghp_…`, `gho_…`).

```bash
trufflehog git file://. --no-update --json | tee /tmp/th-git.json
trufflehog filesystem . --no-update --json | tee /tmp/th-fs.json
```

**Step 2 — Manual keyword-agnostic regex over `git log -p`.** Covers Step 1's blind spot on legacy 40-hex tokens stored under non-GitHub-named env vars.

```bash
# Hex-shaped values in env-var assignments, additions only, full history
git log --all -p \
  | rg -n '^\+.*=\s*["'\''][A-Fa-f0-9]{32,64}["'\'']' \
  | rg -v 'sha256:|sha1:|sha512:|md5:|@v[0-9]|GITHUB_TOKEN|secrets\.'

# Base64-shaped values (Slack, Stripe, signed JWTs without prefix)
git log --all -p \
  | rg -n '^\+.*=\s*["'\''][A-Za-z0-9+/]{40,}={0,2}["'\'']' \
  | rg -v 'sha256:|@v[0-9]'

# Keyword-named secrets on additions
git log --all -p \
  | rg -n -i '^\+.*(api[_-]?key|secret|password|passwd|token|bearer)\s*[:=]\s*["'\''][^"'\'' ]{8,}'
```

**Step 3 — Cross-check every finding at the platform UI.** `Verified: false` from the scanner is not the same as `revoked`. Multiple paths produce that result: actual revocation, OR the verification probe (typically `GET /user`) hits an endpoint scope-blocked for narrow-scope tokens (e.g., `gist`-only). Confirm in the platform UI before declaring a token dead.

- GitHub: <https://github.com/settings/tokens> — look for label, scope, "Last used" timestamp
- AWS: IAM → Access keys
- Stripe / Slack / etc.: each provider's keys page

**Step 4 — OPSEC scan WITHOUT `docs/` exclusions.** Identifying data hides where the scanner-only mindset doesn't look.

```bash
# Comprehensive PII/employer scan — no docs/ exclusion
git ls-files | xargs rg -n 'fxei-meta-project|FedEx|fedex|El Dorado|<corp-domain>|<employer-name>' 2>/dev/null \
  | rg -v 'fonts/|HANDOFF\.md|MEMORY\.md'
```

Redaction targets to enumerate in advance: work emails, employer name, corporate hostnames, GCP project IDs, service-account JSON filenames, internal proxy hostnames, personal home city / address / location info, machine names that imply employer, glyph/tab examples that name an employer.

**Step 5 — Revoke + sweep scope-dependent surfaces.** A `gist`-scope token's blast radius isn't just the repo — it's everything the token's scope grants. For a leaked gist-scope PAT, sweep `https://gist.github.com/<user>` for unauthorized entries. Same logic per scope: deploy-key → deploy keys; workflow → workflow runs.

**Step 6 — If a leaked-value blob lives on an open PR commit, force-push-to-amend (don't fixup).** When the prior commit on the open branch contains the unredacted secret in your postmortem text:

```bash
# Stage the redacted version
git add <postmortem-file>

# Amend the bad commit — bad commit becomes dangling, GC-eligible
git commit --amend --no-edit

# Force-push with lease (safer than --force; aborts if remote moved)
git push --force-with-lease origin <branch>
```

Acceptable trade: PR review threads anchored to the original commit SHA become "outdated" — that is the correct status because they ARE addressed by the amend. The dotfiles repo convention "force-push on owned branches OK" applies (see CLAUDE.md `feedback_commit_approval` carve-out for the broader force-push convention). An additive fixup commit would leave the bad blob reachable via `https://github.com/<owner>/<repo>/commit/<orig-sha>` even after squash-merge.

**Step 7 — Postmortem + explicit history-rewrite decision.** Default for public repos: don't `git filter-repo` rewrite master.

- Public-repo rewrites break every existing clone, fork, archival mirror.
- They don't actually purge content from GitHub's commit cache (direct-SHA URLs keep returning the bad commit until GC runs, hours-to-days for free-plan accounts).
- They add zero security value once tokens are revoked — a dead 40-hex string has no remaining capability.
- Pragmatic posture: revoke + document + accept exposure. Optional: file a [GitHub sensitive-data removal request](https://docs.github.com/en/site-policy/content-removal-policies/github-private-information-removal-policy) to expedite GitHub's GC if the orphaned commits are sensitive enough to warrant it.

### Why each step covers the previous step's blind spot

| Step | Covers | Blind spot it leaves |
|---|---|---|
| 1. Trufflehog scan | Modern prefixed tokens, by structural value-prefix | Keyword-gated on legacy 40-hex |
| 2. Manual regex | Step 1's keyword gate, by value shape | Doesn't verify if tokens are live |
| 3. Platform UI cross-check | Step 1+2's "Verified: false" misreading | Doesn't sweep what the token created |
| 4. OPSEC scan, no docs/ exclusion | Tool-myopia on identifying-but-not-secret data | Per-token, not per-account |
| 5. Scope-dependent sweep | Step 1–4's per-token myopia | Procedural — what to do with findings |
| 6. Force-push-to-amend on PRs | Step 5's procedural blind spot when leak is in-flight | Assumes you decide to keep the bad commit out of master |
| 7. Explicit history-rewrite decision | Step 6's "default to filter-repo because secrets bad" instinct | None — terminal step |

The failure mode the recipe is built around: **silent false-negatives compound**. A scanner that says "0 findings" gives no signal that it has blind spots. Each subsequent step adds a layer whose blind spots are different from the previous, so a true leak has to evade ALL of them to stay invisible.

## Why This Matters

A scanner-only audit produces a confidently-wrong "all clear" — the failure mode is **silent**. There is no error, no warning, no hint that a 40-hex token sitting under a non-GitHub-named env var is invisible to trufflehog's legacy detector. The dotfiles audit found exactly this case: trufflehog flagged one of two adjacent leaked PATs in `bash/.exports` (the one already revoked, because its variable name `HOMEBREW_GITHUB_API_TOKEN` contained the keyword `github_api`) and missed the other (still-live, gist scope, because `HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN` had no GitHub keyword anywhere in the variable name). The audit could easily have been declared complete after only the trufflehog pass.

`Verified: false` misreading compounds the silent-failure mode. Treating it as "revoked" lets a still-live leak ride. The mechanism check is independent of the verification result — confirm at the platform UI.

The OPSEC `docs/` carve-out is the same shape of error: a scope decision that produces a false-clean signal because the scope was wrong. Postmortems and plans live in `docs/`; they routinely mention employer names, project IDs, corporate hostnames, and personal location info as supporting context. Excluding the directory excludes exactly what an attacker would mine for reconnaissance.

Force-push-to-amend prevents in-flight PRs from carrying unredacted secrets into branch history that survives squash-merge. The fixup-commit-on-top instinct is wrong for this specific case — it cleans up the working tree but does nothing about the original commit that's already on the branch. Squash-merge collapses commits onto master, but the original branch commit stays reachable via its SHA URL until GitHub's GC runs.

## When to Apply

- Pre-public-migration audit on any repo about to flip from private to public
- Periodic public-repo audits (quarterly suggested cadence)
- Any time a leaked secret is found in a commit that is part of an open PR (force-push-to-amend, Step 6)
- Any time a secret-scanner reports `Verified: false` on a token in a public repo (cross-check at the platform UI before drawing conclusions, Step 3)
- Any time the audit "feels too clean" on a repo with multi-year history (run Step 2 manual grep regardless of Step 1 result)

## Examples

### Worked example: dotfiles audit, 2026-05-06

See the single-incident postmortem at `docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md` for full evidence. Compressed by step:

- **Step 1**: Trufflehog flagged 1 finding (`HOMEBREW_GITHUB_API_TOKEN`, `Verified: false`).
- **Step 2**: Manual hex grep found a second token (`HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN`) two lines away in the same diff that trufflehog had not surfaced.
- **Step 3**: At <https://github.com/settings/tokens>: trufflehog-flagged token was absent from the list (truly revoked at some prior point). Trufflehog-missed token was present, labeled "Stash", scope `gist`, "Last used within the last 2 years" — **still live**.
- **Step 4**: First-pass OPSEC scan excluded `docs/solutions/`. Re-running without that exclusion found 4 additional files — `corporate-mac-ssl-and-tooling-setup.md` had 6 occurrences alone (GCP project ID `fxei-meta-project` + service-account JSON filename `fxei-meta-project-35631b0c2409.json`). A home-city PII reference in `2026-05-01-001-feat-tmux-location-pill-plan.md` was deeper-class OPSEC than the employer info.
- **Step 5**: Gist sweep at `https://gist.github.com/<user>` — clean.
- **Step 6**: Prior commit `9405805` on the open PR branch contained the literal 40-hex PAT values in the postmortem text. Force-push-to-amend (`git commit --amend` → `git push --force-with-lease`) replaced it with a redacted version using first-6/last-4 fingerprints (`339c6c…0677`, `77a6b9…3d4a`). PR squash-merged as `47a3138` on master.
- **Step 7**: No `git filter-repo` rewrite. Tokens revoked, exposure documented, pre-commit hook ticket filed (issue #69) for write-time prevention.

### Force-push-to-amend, the wrong instinct vs the right move

**Wrong (additive fixup):**

```bash
git add <postmortem-file>
git commit -m "fix: redact PAT values to fingerprints"
git push origin <branch>
# Branch now has 2 commits: original (with unredacted values) + fixup
# Squash-merge collapses onto master, BUT:
# - The original commit remains reachable at /commits/<orig-sha> until GC
# - Anyone with that SHA can still see the unredacted values
```

**Right (force-push-to-amend):**

```bash
git add <postmortem-file>
git commit --amend --no-edit
git push --force-with-lease origin <branch>
# Branch now has 1 commit (the amended version)
# Original commit becomes dangling, GC-eligible immediately on remote
# Direct-SHA URL still works for retention window, but the branch ref no longer points to it
```

The retention-window difference is significant: an additive fixup leaves the bad blob in the branch's commit history for the lifetime of the PR; a force-push-to-amend moves the bad blob out of any reachable ref the moment the push lands.

## Related

- **Worked-example postmortem** (detailed evidence + trufflehog source-code citations): `docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md`
- **Pre-commit hook ticket** (write-time complement to this audit-time recipe): <https://github.com/villavicencio/dotfiles/issues/69>
- **Sibling OPSEC postmortem touched in the same audit pass**: `docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md` — demonstrates why Step 4's docs-inclusive scan matters (six employer-identifying occurrences in this single file)
- **Trufflehog v3.95.2 legacy detector source** (mechanism citation for why Step 2 exists): <https://raw.githubusercontent.com/trufflesecurity/trufflehog/v3.95.2/pkg/detectors/github/v1/github_old.go>
- **GitHub sensitive-data removal policy** (optional Step 7 escalation): <https://docs.github.com/en/site-policy/content-removal-policies/github-private-information-removal-policy>
