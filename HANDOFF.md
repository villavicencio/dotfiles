# HANDOFF — 2026-05-17 (PDT, afternoon)

Continuation of the 2026-05-11 morning session via `/pickup`. **Issue #77 shipped (PR #78, squash-merged `a8e8fe4`), one new bug filed (#79).** Tail end of the session was knowledge-Q&A on mosh and a tmux glyph for the OpenClaw window — no further repo changes.

## What We Built

- **PR #78 — SHA-pin `tailscale/github-action` to v4.1.2** (squash-merged 2026-05-11 19:23 UTC, branch deleted).
  - `.github/workflows/sync-vps.yml:30` — `tailscale/github-action@v4` → `tailscale/github-action@306e68a486fd2350f2bfc3b19fcd143891a4a2d8 # v4.1.2`.
  - Resolved SHA via `gh api repos/tailscale/github-action/commits/v4.1.2 --jq .sha` (annotated-tag-safe path; `git/refs/tags/` returns the tag-object SHA on annotated tags, which is wrong).
  - Closes #77. Completes the SHA-pin sweep started in PR #76 — every third-party action in this repo is now SHA-pinned + comment-tagged.
  - Bonus finding: action ships `runs.using: 'node24'` (confirmed against `curl -sL https://raw.githubusercontent.com/tailscale/github-action/v4.1.2/action.yml`), so this also satisfies the 2026-06-02 Node 20 force-flip deadline. No further deadline-driven action work outstanding.

- **OpenClaw tmux window styled.** Window 1 in the `local` session now carries 🦞 lobster + ember (`#D97757`) via `tmux-window-namer` skill. Persisted to `~/.config/tmux/window-meta.json` (off-repo). Now consistent with the other named windows in the session.

- **Issue #79 filed** — `vps: /root/.dotfiles missing on openclaw-prod — sync-vps.yml broken`, `bug` label. See "What's Next."

## Decisions Made

- **`gh api ... -f ref=v4.1.2`** is the wrong shape for the `contents` endpoint (`-f` sends body params, not query strings). Falling back to direct `curl -sL https://raw.githubusercontent.com/<owner>/<repo>/<tag>/action.yml` is the simpler path when you just need to read a single file at a tag.
- **#79 was filed but NOT auto-fixed.** Re-cloning on the production VPS is shared-state modification — the bug pre-dates this session (last successful Sync VPS run was 2026-05-01, regression sat silent ~10 days), and the ticket body documents three options (re-clone via runbook, decommission, investigate-first). User picks the path.
- **Mosh recommendation:** worth it on flaky/mobile links *if and only if* you always wrap it in tmux. Bare mosh is a footgun (no native scrollback by design — verified against mosh.org). Latest stable is `mosh-1.4.0` (2022-10-27), nothing newer.

## What Didn't Work

- **`gh api repos/.../git/refs/tags/v4.1.2`** for SHA resolution — returns the annotated-tag-object SHA, not the commit SHA. The `commits/<tag>` endpoint is the right one.
- **`gh issue view 77`** had a transient GraphQL TLS handshake timeout mid-session; `gh issue list --state open` succeeded on the same call, so it's flaky-API not flaky-network. Retried, second attempt worked.

## What's Next

1. **Decide on #79** — `/root/.dotfiles` is missing on `openclaw-prod`. Three options listed in the ticket body: re-clone via VPS runbook (`docs/solutions/cross-machine/vps-dotfiles-target.md`), decommission the workflow, or investigate-first what happened. Sync VPS workflow is broken until resolved (workflow itself is fine — the VPS-side directory is the missing piece).
2. **No other open issues, no open PRs.** Repo is otherwise clean.

## Gotchas & Watch-outs

- **Sync VPS workflow is broken end-to-end until #79 is resolved.** Don't run it expecting a successful dry-run — it dies at "Record pre-install SHA" with `cd: /root/.dotfiles: No such file or directory`. The new SHA-pin from PR #78 works correctly (proven by "Join tailnet" succeeding in the failed run); failure is in the next step on the VPS side.
- **`-f` vs `-F` in `gh api`** — `-f` for raw string body params, `-F` for typed (bool/int) body params. Neither sends query strings; use `?key=value` in the URL path for query strings.
- **OpenClaw docker volume still intact on openclaw-prod** — only `/root/.dotfiles` is gone; the Forge backing store at `/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data` is untouched. Forge bridge appends from `/handoff` Step 5/6 still work.
