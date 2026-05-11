# HANDOFF — 2026-05-11 (PDT, morning)

Two-calendar-day-later pickup from the 2026-05-08 handoff. Mostly off-repo: a full Chrome profile clone (David → Goon, ~939MB) and a tmux Volo window setup. **The on-repo work landed #75** — `ci/bump-actions-node-24` branch, PR #76 (squash-merged, branch deleted), all 5 SHA-pinned third-party actions bumped to Node-24-supporting releases 22 days before the 2026-06-02 force-flip. **1 new commit on master (`9280f1e` via merge of PR #76), 1 new follow-up ticket (#77), all carry-forward user-side todos from 2026-05-08 cleared.**

## What We Built

### `9280f1e` — `ci: bump SHA-pinned actions to Node 24 releases (closes #75) (#76)`

Squash merge of PR #76, 2 files / +7 / -7. All 5 third-party actions pinned in `.github/workflows/install-matrix.yml` and `.github/workflows/publish-ci-image.yml` bumped from Node-20 releases to the latest stable Node-24 releases. SHA-pinning convention from PR #57 preserved; trailing `# vX.Y.Z` comments normalized to explicit semver on each pin (was mix of `# v4.3.1`, `# v4`, `# v3`, `# v6` — now uniformly `# v6.0.2`, `# v5.0.5`, etc.).

| Action | From → To | Major bump |
|---|---|---|
| `actions/checkout` | `34e1148` `# v4.3.1` → `de0fac2` `# v6.0.2` | v4 → v6 |
| `actions/cache` | `0057852` `# v4.3.0` → `27d5ce7` `# v5.0.5` | v4 → v5 |
| `docker/login-action` | `c94ce9f` `# v3` → `4907a6d` `# v4.1.0` | v3 → v4 |
| `docker/setup-buildx-action` | `8d2750c` `# v3` → `4d04d5d` `# v4.0.0` | v3 → v4 |
| `docker/build-push-action` | `10e90e3` `# v6` → `bcafcac` `# v7.1.0` | v6 → v7 |

SHA resolution method (preserves it for the next sweep): `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha` — uses the `commits/` endpoint, which dereferences lightweight or annotated tags to the canonical commit SHA in one call. Don't use `git/refs/tags/<tag> --jq '.object.sha'` — that returns the tag-object SHA for annotated tags, not the commit SHA, and you'd need a second call to dereference.

Acceptance evidence (all on-record in PR #76):
- install-matrix.yml on PR #76: linux 1m10s pass, macos 13m28s pass.
- publish-ci-image.yml auto-fired on merge (touched its watched path `.github/workflows/publish-ci-image.yml`) — all 21 steps `success`, including post-#71 5-assertion smoke-test gate.
- "Node.js 20 actions are deprecated" annotation absent from both install-matrix and publish-ci-image check-run annotations APIs (`[]` returned).

### Issue #77 filed — `ci: SHA-pin tailscale/github-action + verify Node 24 readiness in sync-vps.yml`

Surfaced during the #75 sweep. `sync-vps.yml:30` uses `tailscale/github-action@v4` — a **mutable major-version tag**, violating the PR #57 SHA-pin convention. Two concerns folded into one ticket:
1. Supply-chain risk (mutable tag + `TS_OAUTH_*` secrets + tailnet access to prod VPS).
2. Node 24 readiness — never verified during #75 because it wasn't in the enumerated 5.

Ticket is labeled `enhancement`, not blocking, includes the full verification recipe + acceptance criteria. Should fold into the same 2026-06-02 urgency window IF the action turns out to be JS on Node 20.

### Off-repo: Chrome profile clone (David → Goon)

User requested a full duplicate of their Chrome `Default` profile to a new "Goon" profile for sign-in into a different Google account. Method:
1. Verified Chrome was fully quit (Cmd+Q + `pgrep` sanity).
2. Backed up `~/Library/Application Support/Google/Chrome/Local State` to a `.backup-pre-clone-*` sibling.
3. `cp -R "Default" "Profile 1"` (~939MB; ~21MB lighter than source because live caches/sockets skipped — normal).
4. Python-patched `Local State`: deep-copied `Default`'s `profile.info_cache` entry to `Profile 1`, changed `name` to "Goon", set `is_using_default_name: false`, appended to `profiles_order`.
5. Chrome relaunched, picker shows both profiles.
6. User signed out of David's Google account inside Goon (chose "Keep your data" on the sync-off prompt), signed in to new account.

User confirmed clone landed cleanly. Backup deleted on confirmation.

### Off-repo: tmux Volo window setup

New 5th tmux window created in the `local` session via `tmux new-window -n Volo`. Styled via the `tmux-window-namer` skill convention — glyph `\U000F0BC9` (`nf-md-space-invaders`, NOT airplane as I initially miscalled it), palette **lilac** `#C678DD` (CRT/synthwave arcade glow). Persisted to `~/.config/tmux/window-meta.json` via `~/.config/tmux/scripts/save-window-meta.sh` so it survives tmux restarts.

Memory written: `memory/project_tmux_window_volo.md` — captures that Volo = game-focused workspace, the glyph is space-invaders not airplane, palette is lilac. Future `/pickup` sessions will know this without re-asking.

## Decisions Made

- **Merge-without-asking is now standing policy on the dotfiles repo.** User said "Yes and please feel free to do so going forward on this project" after I asked whether to merge PR #76. Saved to `memory/feedback_commit_approval.md` as the "Merge rule (added 2026-05-11)" section. Scope: dotfiles repo only — don't generalize. Commit-+-push gates (the older rules) still apply at the "should this be committed at all" boundary; merge of an already-opened PR with green CI is implied authorization.

- **Tier 1 code review (self-review + CI as the verifier) was sufficient for PR #76.** Shipping-workflow says Tier 2 for sensitive-surface diffs (workflow YAML with `packages: write` + dependency manifests both qualify), but the diff was 7 mechanical lines and CI literally executed the new pins. Called it Tier 1 explicitly and surfaced the tradeoff to the user before merging. Pattern worth re-using: pure dependency bumps that CI exercises end-to-end don't need a separate review pass.

- **Squash-merge for PR #76**, not `--merge`. Single-commit clean history on master matches the existing pattern (every prior PR landed squash-merged per `gh pr list --state merged`).

- **Issue #77 split off as a separate ticket**, not folded into #75 retroactively. The issue body for #75 explicitly enumerated 5 actions; tailscale wasn't one of them. Filing as a follow-up keeps the audit trail clean — #75 closes against its exact stated scope; #77 captures the discovered out-of-scope work.

- **Goon profile clone uses `--adopt`-style logic at the Local State layer**, not a fresh profile + manual data import. Reason: bookmarks, extensions, history, cookies, saved passwords, autofill all carry verbatim with `cp -R + Local State patch`; Chrome's "import from another profile" UI is partial and skips extensions. The clone path also preserves the `Chrome Safe Storage` keychain link transparently (per-app key, not per-profile), so site logins don't re-prompt.

- **Sky → lilac palette swap on the Volo tmux window** after the user clarified the glyph was space-invaders. The original sky pick was made under my wrong "airplane / flight" assumption — once the game-focused meaning surfaced, lilac (CRT-purple, synthwave) fit the arcade vibe much better than sky.

## What Didn't Work

- **`gh pr checks --watch` died on a network reset mid-watch.** After 5+ minutes of refreshing, the underlying `Post https://api.github.com/graphql` connection got `read: connection reset by peer` and the watch exited 1. Linux already passed by then; macos was still pending. Recovered by re-querying `gh pr checks 76` once the user got the failure notification. Lesson: for long CI watches, treat `--watch` death as a network blip, not a CI failure; always re-check state once before assuming the worst.

- **`ruby -ryaml -e ...` in a non-interactive Bash shell** triggered an infinite recursion of `_load_rvm` shims (zsh-side lazy-loader behavior tries to bootstrap inside a non-interactive shell context, repeatedly). Symptom: `command not found: _load_rvm` cascade until `maximum nested function level reached; increase FUNCNEST?`. Fixed by calling `/usr/bin/ruby` directly, bypassing the rvm shim. Worth folding into the zsh lazy-loader notes — the rvm shim is currently unguarded against non-interactive contexts.

- **`python3 -c "import yaml"`** failed before falling back to ruby — system `python3` (`/usr/bin/python3`) doesn't have PyYAML in its site-packages. Skip straight to `/usr/bin/ruby -ryaml` for YAML-validity smoke checks; the Apple-system ruby ships with yaml in the stdlib.

- **Initial `pgrep | head | || echo`** pattern (`pgrep -lf "Google Chrome" | head -3 || echo "(none)"`) doesn't fire the `||` branch when pgrep finds nothing — `head` succeeds with empty input (exit 0), so the `||` never triggers. Symptom: the "(none)" branch never prints, but a non-zero exit propagates through. Use `pgrep -qf <pattern>; [ $? -eq 0 ] && echo "running" || echo "not running"` or `pgrep -f <pattern> >/dev/null && echo running || echo "not running"` instead. Cosmetic only, but the pattern is incorrect.

## What's Next

1. **(New, optional) Triage #77 — tailscale/github-action SHA-pin + Node 24 readiness.** Not blocking. Should fold into the 2026-06-02 urgency window IF the action turns out to be JS on Node 20. Verification recipe is in the ticket body. Per the user's standing rule, needs a new branch (no ticket work on master). Touches `.github/workflows/sync-vps.yml` only (one line). Expect ~10-min job total.

2. **(No carry-forwards.)** All four prior-handoff user-side todos cleared today:
   - iCloud cleanup — done (user confirmed it cleared the reappearing CloudKit paths)
   - Setapp cancellation — done (user confirmed mid-session)
   - `mac-cleanup --force` to free ~20GB — done (user confirmed mid-session)
   - Cowork OAuth bug feedback to Anthropic — still in user's optional bucket, but no longer load-bearing on this repo

3. **(Continuing, monitoring) Cowork OAuth bug in Claude Desktop 1.6608.0** is still upstream-only. No change. Workaround remains: use `claude.ai/task/new` in any browser. Diagnostic payload is in the 2026-05-08 handoff if/when the user decides to file it.

## Gotchas & Watch-outs

- **`gh api repos/<owner>/<repo>/commits/<tag> --jq '.sha'`** is the right SHA-resolution call for action pins. `git/refs/tags/<tag> --jq '.object.sha'` returns the *tag-object* SHA for annotated tags, not the commit SHA — using that would put a non-commit SHA in a `uses:` line and GH Actions would refuse to resolve it. Future Node-N or just-because-bumps should use the `commits/` endpoint.

- **`actions/checkout` jumped v4 → v6 (skipped v5).** That's not a typo; v5 was a short-lived prerelease line. Sanity-check the latest-release tag before assuming the major increment is `+1`.

- **`docker/build-push-action@v7` changed attestation defaults**, but we already set `provenance: false` explicitly which is the conservative choice. If a future change re-enables attestation defaults, the digest-pin contract in install-matrix.yml breaks (SLSA attestation produces a manifest list that complicates digest pinning — comment is in publish-ci-image.yml line 78-80).

- **`tailscale/github-action@v4` in sync-vps.yml is still on a mutable tag** post-#75. Tracked in #77 but worth keeping top-of-mind — that workflow has `TS_OAUTH_*` secrets and reaches the prod VPS. Don't add new third-party actions to *any* workflow without applying the PR #57 SHA-pin convention.

- **Local State backup-on-write pattern for Chrome profile edits.** Before any Python-patch of `~/Library/Application Support/Google/Chrome/Local State`, snapshot it to `Local State.backup-pre-<reason>-<timestamp>`. The file is structurally simple JSON but a stray syntax error renders Chrome's profile picker unusable on next launch.

- **Chrome profile-picker visibility hinges on `profile.profiles_order`.** Not just `profile.info_cache` — the `_order` array is what the picker UI reads. If you only patch `info_cache`, the new profile exists but doesn't show up in the chooser. Both must be updated.

- **`Chrome Safe Storage` keychain entry is per-app, not per-profile.** A profile clone WILL preserve site logins and cookies because the encryption key didn't change. This is sometimes desirable (full duplicate including session state) and sometimes not (you wanted a sandbox without inherited logins) — call it out to the user up front rather than surprising them.

- **`actions/cache@v5` bumped the internal cache-service protocol.** Public inputs (`path` / `key` / `restore-keys`) are unchanged, but caches saved by v4 may not restore cleanly to v5 if the cache-service handshake changed. First few runs after this PR may see cold restores on the macos leg until the v5 caches build. Don't read low-restore-rate as a regression for ~1-2 days.

- **The `/handoff` skill's Forge bridge writeback step is opt-in via `forge-project-key:` in CLAUDE.md.** This repo has `forge-project-key: dotfiles`, so the skill WILL attempt the writeback. No durable cross-project learnings worth pushing this session — the SHA-bump recipe is project-specific, the Volo tmux setup is workspace-specific. Skip silently.

- **`--no-verify` was NOT used this session.** All commits (just one direct: the squash-merge `9280f1e`) passed gitleaks pre-commit cleanly. Streak continues.
