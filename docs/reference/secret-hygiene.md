# Secret hygiene

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Secret hygiene
**This repo is public.** Don't name David's employer or describe what his work agents are for
(Axiom is just "the `axiom` profile"); the audit recipe in
`docs/solutions/best-practices/public-repo-secret-audit-recipe-2026-05-06.md` greps for it.
Gitleaks doesn't catch plain words. Seen 2026-10-21 on #234.

Every commit is scanned by gitleaks via a `pre-commit` hook. Config lives in
`.pre-commit-config.yaml` at repo root, the hook is wired by `helpers/install_pre_commit.sh`,
and `./install` runs that helper automatically on both macOS and Linux.

The hook entry is `gitleaks git --pre-commit --redact --staged --verbose` — only
**staged diffs** are scanned, not the full working tree or history. The historical
`bash/.exports` leak (fingerprinted in
`docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md`)
is invisible to the hook by design — manual audits + the postmortem's grep recipe handle history.

**Entropy gate.** Gitleaks's `github-pat` rule (and most provider rules) include an
entropy threshold to avoid false positives on test fixtures. A token like
`ghp_aaaaaaaa...` (entropy 0) is *not* flagged by design. To smoke-test the hook,
use a high-entropy fake like `ghp_xKy7mFP2zL9QrT4vN8bH3sD1jE6cWa0pIuYg`. <!-- gitleaks:allow -->

**False positives.** Add an inline `# gitleaks:allow` comment on the offending line,
or extend the repo with a `.gitleaks.toml` allowlist entry. Default ruleset is broad —
some collisions on UUIDs / hex SHAs / fixture data are expected over time.

**Intentional bypass.** `git commit --no-verify`. Reflog records the bypass but not the
*why*; document the reason in the commit message body when bypassing on purpose, so the
audit trail distinguishes "I knew" from "I forgot the hook exists."

**Upstream gotcha — `pass_filenames: false` override is required.** Gitleaks's published
`.pre-commit-hooks.yaml` for the `gitleaks-system` variant omits `pass_filenames: false`
(the `gitleaks` and `gitleaks-docker` variants set it correctly). Without our local
override in `.pre-commit-config.yaml`, pre-commit appends each staged filename as a
positional arg, gitleaks fails with `cannot change to '<file>': Not a directory`, and
the hook silently reports "no leaks found" on every commit — verified against
gitleaks v8.30.1. If gitleaks's hook config ever fixes this upstream, the override
becomes a harmless no-op.

**Version pin.** Gitleaks version is pinned in three places that must match: the `rev:` in
`.pre-commit-config.yaml`, `GITLEAKS_VERSION` in `helpers/install_pre_commit.sh`
(used for the Linux binary download), and the `Gitleaks.Gitleaks` `Version` in
`windows/packages.json`. Bump all three together.
