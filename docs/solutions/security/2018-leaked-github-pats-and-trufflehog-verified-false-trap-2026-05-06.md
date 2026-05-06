---
title: "Two 2018 GitHub PATs leaked in bash/.exports git history — and why trufflehog's legacy hex detector silently skipped one of them"
date: 2026-05-06
category: security
tags:
  - secret-leak
  - github-pat
  - git-history
  - trufflehog
  - public-repo
  - opsec
  - false-negative
  - keyword-gated-detection
severity: Medium
component: "git history of public dotfiles repo (bash/.exports, removed in 7c05ea9 but still reachable via `git log -p --all`)"
symptoms:
  - "Audit pass on a public dotfiles repo turned up two hardcoded `export FOO=\"<40-char hex>\"` lines from 2018 that were deleted from the working tree but still live in commit history"
  - "Trufflehog flagged exactly one of the two tokens and reported `Verified: false`; the second token, sitting two lines away in the same diff, was not flagged at all — not even as an unverified candidate"
  - "GitHub's PAT page listed the unflagged token as still present, scope `gist`, with a 'Last used within the last 2 years' timestamp — the still-live leak was the one trufflehog had not surfaced"
  - "Manual `git log -p | rg` cross-check found the missed token in seconds; the audit could easily have been declared 'clean' after only the trufflehog pass"
problem_type: "Long-lived secret leak in public git history + secret-scanner false-negative driven by keyword-gated detection on legacy 40-hex tokens"
module: "git history (specifically commits 34f1147 → 7c05ea9 in this repo) and secret-scanning workflow"
related_solutions:
  - "docs/solutions/best-practices/public-repo-secret-audit-recipe-2026-05-06.md — generalized recipe + force-push-to-amend pattern distilled from this incident; this postmortem is the worked-example evidence the recipe references"
---

## TL;DR

Two GitHub Personal Access Tokens were committed in plaintext to `bash/.exports` in commit `34f1147` (2018-11-02), removed from the file in `2314d3b`, and the file itself was deleted in `7c05ea9` ("Convert dotfiles over to Dotbot"). The repo went public somewhere between then and now. The tokens stayed in history.

```
HOMEBREW_GITHUB_API_TOKEN="339c6c…0677"   # legacy GitHub PAT, env-var name contains "GITHUB"
HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN="77a6b9…3d4a"   # legacy GitHub PAT, scope: gist, env-var name has no GitHub keyword
```

(Token values redacted to first-6/last-4 fingerprints. The full 40-char hex values are in the original commit `34f1147` if forensic recovery is needed; reproducing them in the current tree would just make HEAD trip every secret scanner that runs against it.)

A 2026-05-06 secret-audit pass on the repo found them. Trufflehog flagged the first as `Verified: false` and **did not flag the second at all**. Manual `git log -p` cross-check turned up the second one immediately. The unflagged one turned out to be the still-live one — labeled "Stash" on GitHub's PAT page, gist scope, last used within the past two years. The Homebrew one had already been revoked at some point in the intervening years.

The headline lesson is not "rotate your tokens" (that's table stakes). It's that **trufflehog's legacy GitHub PAT detector is keyword-gated** — a 40-char hex value only becomes a detection candidate if a GitHub-flavored keyword (`github`, `gh_pat`, `github_token`, etc.) appears immediately before it in the variable-name prefix. `HOMEBREW_GITHUB_API_TOKEN` matched (the regex sees `github_api`); `HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN` did not (no GitHub keyword anywhere in the variable name). The second token was never even a candidate, which is meaningfully different from "it failed verification." Pairing trufflehog with a keyword-agnostic manual hex scan over `git log -p` is the cheap fix.

## What happened

### The introduction (2018-11-02)

Commit `34f1147` "Add additional config" created `bash/.exports` with the two tokens hardcoded (values redacted here, full strings recoverable from the commit):

```bash
# Gist-scope token for HyperTerm backup plugin.
export HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN="77a6b9…3d4a"
...
export HOMEBREW_GITHUB_API_TOKEN="339c6c…0677"
```

Both are 40-char lowercase hex — the pre-2021 GitHub legacy PAT format, before GitHub introduced prefixed tokens (`ghp_…`, `gho_…`, etc.) that secret scanners can recognize structurally. That's relevant: with the prefixed format, the scanner has a high-precision regex on the value itself. With the legacy hex format, the scanner has only a 40-char hex regex — far too noisy on its own — so it gates on keyword adjacency in the variable-name prefix. That gating is the whole reason one of these two tokens slipped past the scan.

### The "removal" (2018-onward)

Commit `2314d3b` "Update history settings" removed both lines from `bash/.exports`. Commit `7c05ea9` ("Convert dotfiles over to Dotbot") deleted the file entirely. Both events leave the secrets in history — `git log -p --all` reads them right back out. Standard pattern, well-known trap.

### The audit (2026-05-06)

Triggered by a routine "is anything bleeding from this public repo" pass. Two scanners run in parallel:

```
trufflehog git file://. --no-update --json
trufflehog filesystem . --no-update --json
```

Working-tree scan: clean. History scan: **one** finding, the `HOMEBREW_GITHUB_API_TOKEN`, marked `Verified: false`. Reasonable-but-wrong next-step interpretation: "scanner did its job, only one finding, this one is invalid, audit complete."

Manual `git log -p` cross-check turned up the second token — `HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN` — sitting two lines away in the same diff. Trufflehog had not flagged it at all. Verifying against GitHub's PAT UI then showed:

- `HOMEBREW_GITHUB_API_TOKEN` — not present in the PAT list. Already revoked at some point. Trufflehog's `Verified: false` was correct in this case.
- `HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN` — present, labeled "Stash", scope `gist`, "Last used within the last 2 years." **Still live.**

So one of the two was already revoked, the other was reachable AND being used. Containment action: delete the live token via the GitHub UI; sweep gists at `https://gist.github.com/<user>` for anything attacker-created with the leaked credential.

## Why trufflehog skipped the live one

Reading the source ([trufflehog v3.95.2 `pkg/detectors/github/v1/github_old.go`](https://raw.githubusercontent.com/trufflesecurity/trufflehog/v3.95.2/pkg/detectors/github/v1/github_old.go)), the legacy 40-hex GitHub PAT detector is built as:

```
detectors.PrefixRegex([...github-flavored keywords...]) + `\b([0-9a-f]{40})\b`
```

The `Keywords()` method returns `["github", "gh"]`, but those are only used as a coarse chunk-level pre-filter so the detector can skip files that obviously don't mention GitHub. The actual per-match regex requires a GitHub-flavored prefix (`github_token`, `gh_pat`, `github_api`, etc.) immediately before the 40-char hex value to register a candidate at all.

That gating cleanly explains the asymmetric behavior:

- `HOMEBREW_GITHUB_API_TOKEN="339c6c…"` — the variable name contains `_GITHUB_API_`, so the prefix regex matches `github_api` immediately before the hex. Detector emits a candidate, sends it to verification, the verification call to `GET /user` returns 401/403 (the token had been revoked previously), trufflehog records `Verified: false`. Correct outcome.
- `HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN="77a6b9…"` — variable name contains no GitHub-flavored substring at all. Prefix regex fails. **No candidate is ever emitted.** Verification is never invoked. Trufflehog never sees the token, so no finding appears in the JSON output.

The original framing of this lesson was different — it claimed `Verified: false` was the misleading signal because narrow-scope tokens fail the `/user` verification probe. That framing is wrong for *this* incident: the missed token never reached the verification stage at all, so the verification mechanism is irrelevant to why it was missed. (The narrow-scope-verification-failure pattern is a separately real concern and would matter if HYPERTERM had ever become a candidate, but it didn't.)

## The headline lesson

**Trufflehog's legacy 40-hex GitHub PAT detector is keyword-gated by the variable-name prefix immediately before the value. Tokens stored under env-var names that don't contain a GitHub keyword (`HYPERTERM_*`, `HOMEBREW_INSTALL_*`, `MY_APP_TOKEN`, `STASH_*`, anything-not-named-after-GitHub) are invisible to the legacy detector — not flagged-and-unverified, but not surfaced at all.**

The new GitHub detector ([v2 `github.go`](https://raw.githubusercontent.com/trufflesecurity/trufflehog/v3.95.2/pkg/detectors/github/v2/github.go)) catches modern prefixed tokens (`ghp_…`, `gho_…`, etc.) by their structural prefix on the value itself and is keyword-independent. But anything still in the legacy 40-hex format — and there are millions in the wild from pre-2021 — only gets caught by a detector that needs the variable-name prefix to look like GitHub. That is the gap.

The audit posture has to be:

1. Don't trust "trufflehog returned N findings" as a complete count for repos that may contain pre-2021 hex secrets — pair the scan with a keyword-agnostic manual hex-env grep over `git log -p`.
2. When a token IS surfaced and marked `Verified: false`, separately confirm "dead" at the platform UI (GitHub PAT page, AWS IAM keys page, etc.) — verification failure is also possible from narrow-scope tokens that probe the wrong endpoint, so the verdict needs human cross-check.
3. Don't take "the scanner found one finding" as "the scanner found all findings" — for high-stakes repos (public, long history, ancient commits), assume the scanner has blind spots and run the manual grep recipe below regardless.

## Why no history rewrite

Considered and rejected. The repo is public, has many years of history, and may have been cloned/forked by others. Force-pushing a `git filter-repo` rewrite:

- Breaks every existing clone (collaborators, archival mirrors, GitHub's own dangling-ref retention).
- Doesn't actually purge the leaked content from GitHub's commit cache — direct-SHA URLs (`https://github.com/<owner>/<repo>/commit/<sha>`) keep returning the bad commit for hours-to-days afterward unless GitHub Support garbage-collects on request via their [sensitive-data removal policy](https://docs.github.com/en/site-policy/content-removal-policies/github-private-information-removal-policy).
- Adds zero security value once the tokens are revoked. A dead credential in history is a 40-char hex string with no remaining capability.

The pragmatic posture: revoke + document + accept exposure. Future-me reading this should confirm both tokens are truly revoked at the platform UI before deciding the residual risk is zero.

## Containment actions taken (2026-05-06)

1. `HYPERTERM_SYNC_SETTINGS_PERSONAL_ACCESS_TOKEN` ("Stash") deleted via GitHub PAT UI. Confirmed by user same-session.
2. Gist sweep — user confirmed no unauthorized entries in the gist list.
3. This postmortem written; PAT values redacted to first-6/last-4 fingerprints throughout so HEAD does not trip future secret scanners.
4. **Comprehensive employer-identifying-info redaction across all tracked files** — `CLAUDE.md` (work-email references, machine table row, work-Mac setup section), `git/gitconfig` (commented-out work-email example), `.github/workflows/install-matrix.yml` (corporate-proxy comment), `claude/commands/critique.md` (corporate-Mac comment), `docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md` (six occurrences including the GCP project ID and service-account JSON filename), `docs/ideation/2026-05-02-dotfiles-improvements-ideation.md`, plus tmux-glyph examples in two plan/brainstorm docs. Personal home-city reference in `docs/plans/2026-05-01-001-feat-tmux-location-pill-plan.md` also redacted to a generic placeholder.
5. **GitHub issue filed** for adding gitleaks/trufflehog as a pre-commit hook so the next instance of this gets caught at write-time rather than depending on a manual audit pass.

## What to grep for next time

When auditing this class of repo (dotfiles, shell-config, anything with shell-style env exports), trufflehog alone is not sufficient. The companion manual-grep pass that caught the second token here:

```bash
# Hex-shaped values in env-var assignments, additions only, full history
git log --all -p \
  | rg -n '^\+.*=\s*["'\''][A-Fa-f0-9]{32,64}["'\'']' \
  | rg -v 'sha256:|sha1:|sha512:|md5:|@v[0-9]|GITHUB_TOKEN|secrets\.'

# Base64-shaped values (Slack tokens, Stripe keys, signed JWTs without prefix)
git log --all -p \
  | rg -n '^\+.*=\s*["'\''][A-Za-z0-9+/]{40,}={0,2}["'\'']' \
  | rg -v 'sha256:|@v[0-9]'

# Specific keyword scan on additions
git log --all -p \
  | rg -n -i '^\+.*(api[_-]?key|secret|password|passwd|token|bearer)\s*[:=]\s*["'\''][^"'\'' ]{8,}'
```

These three together catch:
- Pre-2021 GitHub legacy PATs (40-char hex)
- AWS legacy access keys without the `AKIA…` prefix (rare, but possible in old configs)
- Slack/Stripe-shaped base64 tokens
- Anything labeled with an obvious secret-name keyword

Pair the scan with a platform-UI cross-check on whatever account the leaked token belonged to. A scanner that returns zero findings on a repo that has 40-hex secrets stored under non-GitHub-named env vars is reporting a true-by-its-own-rules result that is also wrong about the world.

## Why this is a learning worth keeping

Two reasons. First, the keyword-gating blind spot in trufflehog's legacy GitHub detector is exactly the kind of pitfall that compounds across audits — once you know it exists, every future audit on a repo with pre-2021 history benefits from the manual hex-env grep as a paired step. Second, the manual-grep recipe in the section above is reusable infrastructure: copy-paste those three commands into the next audit and they produce keyword-agnostic coverage independent of which scanner you run, so they don't inherit any single tool's blind spots.

The gravitational center of the lesson is **not** "rotate your tokens" — it's **"know the shape of your scanner's blind spots and pair it with a tool whose blind spots are different."** For trufflehog v3.95.2, that means pairing the legacy 40-hex detector (keyword-gated, blind to non-GitHub-named env vars) with a keyword-agnostic regex like the one above.
