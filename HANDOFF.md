# HANDOFF — 2026-04-21 (afternoon PST, same-session continuation of pickup-from-morning flow)

## What We Built

### Shipped to master (2 PRs merged, both squash)

**PR #44 `f57b063` — VPS runbook dry-run callout + /handoff Perry→Forge migration + path-trap hardening.**

- **New §6 in `docs/solutions/cross-machine/vps-dotfiles-target.md`** — "What `dry_run=true` actually does." Placed between the Tailscale smoke test (§5) and the Pre-Deploy Go/No-Go Checklist. Captures the two independent signals the workflow surfaces in dry-run mode: (a) pending-commits list in the step summary is the authoritative "what would land" signal, (b) `./install --dry-run` runs against the VPS's current HEAD, not origin/master, so new `- link:` entries in pending commits won't render as "Would create symlink" until apply. Links back to the full analysis in `sync-vps-dry-run-previews-current-head.md`. Closed the oldest open runbook-to-do item (carry-forward from 2026-04-18).
- **`/handoff` Step 6 migrated Perry→Forge in `claude/commands/handoff.md`** — replaces the Discord-mention + TUI-chat-completion Perry briefing (Perry retired 2026-04-20) with a simple ssh-append to Forge's per-project `cadence-log.md`. Uses the host-volume root `/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/workspace-forge/projects/{key}/` so it matches `/pickup` Step 2c — commands run over plain ssh, not `docker exec`, so the container-internal `/home/node/...` path would silently create a shadow tree the bridge never reads. Block comment above the ssh invocation documents the trap.
- **`/handoff` Step 5 paths fixed in the same commit** — two ssh-based writes (approved-items append, audit-log append) had the same container-internal `/home/node/.openclaw/...` paths. Both rewritten to the host-volume root; intro prose carries a one-sentence callout cross-referencing the 2026-04-20 shared Forge learning. Caught by reviewer after the initial Step 6 fix — classic "fix one instance, miss the siblings."

**PR #45 `4fecda5` — Claude Code statusline pulled into dotfiles + git-branch segment added.**

- **`claude/statusline-command.sh` added to the repo** — previously unmanaged at `~/.claude/statusline-command.sh`, only existed on the personal Mac. Linked via `install.conf.yaml` alongside `settings.json` so it lands on any Darwin host via Dotbot. Darwin-only per the existing `~/.claude/*` convention (Linux/VPS skips `~/.claude/*` in `install-linux.conf.yaml`).
- **New git-branch segment between path and model** — renders the current branch with the Powerline branch glyph (U+E0A0). `master`/`main` render dim white (default, low visual weight); any other branch renders magenta so the working-branch name pops. Hidden when not in a git repo or on detached HEAD. Color-coded by working-vs-default, not arbitrary.

### Operational events (not commits)

- **PR #44 reviewed iteratively** — three rounds of review-comment-resolver feedback. Round 1 flagged the Step 6 shadow-path bug (my initial migration used `/home/node/...`). Round 2 flagged that Step 5 still had the same bug (I'd only fixed Step 6). Round 3 was all-clear. Force-push-with-lease on both rounds; HANDOFF.md was dropped from the PR entirely after round 1 raised "committed HANDOFF is stale by merge time."
- **HANDOFF.md intentionally kept uncommitted mid-session.** Yesterday's session state was committed ahead of this PR then yanked. The rule that emerged: never commit HANDOFF.md mid-session; let the next `/handoff` regenerate it fresh against post-merge master.
- **Stray `claude/commands/handoff.md` modification from yesterday landed in PR #44** — it was the Perry→Forge Step 6 migration, written but never committed. Yesterday's handoff flagged it as "origin unknown, decide whether to commit/revert/stash." Verdict: legit, committed.
- **Backup discipline during statusline swap.** Copied `~/.claude/statusline-command.sh` → `.pre-dotfiles-bak` before `rm`, ran Dotbot, confirmed symlink + live render, then deleted the backup. No data loss path.

## Decisions Made

- **`dry_run=true` doc lives at the runbook level, not just the solution doc.** The `sync-vps-dry-run-previews-current-head.md` solution doc from 2026-04-17 already had the full analysis and its Prevention section explicitly asked for a one-liner back-ported into the runbook. Back-ported with a compact §6 rather than inlining the whole analysis — the runbook links to the solution doc for operators who want the why.
- **All Forge-bridge ssh writes use the host-volume root, period.** The `/home/node/...` container-internal path is ONLY valid inside `docker exec`. Every `ssh root@openclaw-prod 'cmd'` flow must use `/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/...`. Both fixed + documented inline with a pointer to the 2026-04-20 shared Forge learning. This is the third related bug caught in two days — the shared learning is earning its keep.
- **Never commit HANDOFF.md mid-session.** Even with "unrelated stray mod" as cover, a committed mid-session snapshot becomes stale the moment any commit lands later on the same branch. `/handoff` regenerates from scratch at end-of-session; committing earlier just creates work for the next `/pickup` to un-learn.
- **Statusline branch color scheme: dim-on-default, magenta-on-working-branch.** User's intuition ("99.9% of the time I'm on a branch") argued for making the branch name visible without making every render noisy. Dim master/main + magenta others is the honest encoding — "if you see color, you're not on default."
- **U+E0A0 encoded as literal UTF-8 bytes in the shell script.** Two reasons: bash 3.2 `printf` doesn't interpret `\uXXXX` (verified), and the Claude Code Write tool strips PUA-range characters outright (per `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md`). `\xee\x82\xa0` bypasses both.
- **Statusline is Darwin-only (keeps existing `~/.claude/*` convention).** Linux VPS has no TUI session rendering Claude Code's statusline — adding it to `install-linux.conf.yaml` would be dead config.

## What Didn't Work

- **Amending the wrong commit on PR #44 round 2.** After fixing Step 5's paths, I ran `git commit --amend --no-edit`, which amended the *most recent* commit — the VPS runbook commit, not the handoff-migration commit where the Step 5 change belonged. Had to `git reset --mixed master` and redo both commits from scratch. *Why it happened:* `--amend` acts on HEAD; if HEAD is the wrong commit for the change you just made, `--amend` silently does the wrong thing. Next time: verify `git log --oneline` before `--amend`, or use explicit `git commit --fixup=<sha>` + rebase.
- **`printf "...\uE0A0..."` in the initial statusline script.** Output was the literal 7-char string `\uE0A0`, not the glyph. bash 3.2's `printf` doesn't interpret `\u`. Caught before commit by testing in `/bin/sh` directly.
- **Pasting literal PUA glyph into the Write tool (considered, not tried).** Would have been stripped to empty by the Write tool — the exact issue documented in the PUA-glyphs solution doc. Skipped straight to `\x` hex-byte encoding.
- **`./install` in foreground during the statusline swap (tried, timed out).** The full install pipeline runs OMZ, brew, Brewfile, nvm, node — minutes. Claude's bash 2-min default timed out. Ran `./dotbot/bin/dotbot -d "$PWD" -c install.conf.yaml` directly instead, which is the link-step-only fast path.

## What's Next

Prioritized:

1. **First end-to-end `/handoff` run exercising the new Step 6 ssh-append** — the cadence-log write path was validated by inspection only, not by real execution. This handoff itself is the first live test. If the heredoc + escaped `$DEST` quoting breaks, catch it here.
2. **Next branch switch exercises the statusline color rule** — feature branch → magenta, then back to master → dim. Cheap visual confirmation the case statement is right.
3. **`tmux-window-namer` could pull in branch-awareness too.** Not on anyone's list, but the new statusline branch detection (`git -C "$cwd" symbolic-ref --short -q HEAD`) is identical to what a per-tab "what branch is this window working on?" feature would need. Defer until asked for.
4. **Still open from the 2026-04-20 handoff** — OpenClaw gateway MCP-reaper leak (not dotfiles), Syncthing healthcheck misconfig (not dotfiles), OAuth rotation reminder (2027-04-14 calendar). No new dotfiles-scoped items.

## Gotchas & Watch-outs

- **`/handoff` skill loaded from session-start may be stale after a skill-file merge.** This session's `/handoff` invocation rendered Steps 5 and 6 with the pre-PR-#44 `/home/node/...` paths even though the fix had already merged to disk. I had to consciously use the on-disk paths when executing. Next session: `/clear` before `/handoff` if the skill file changed during the session, or confirm the displayed path matches the on-disk file.
- **Dotbot `force: true` is NOT set.** The statusline swap required manually `rm ~/.claude/statusline-command.sh` before Dotbot would overwrite the regular file with a symlink. `relink: true` (which IS set) only handles symlink→symlink; it refuses to touch regular files. Next time a file gets pulled into the repo, expect the same `"already exists but is a regular file"` error and the same rm-then-relink workflow. Do NOT globally flip `force: true` — too much blast radius on the rest of the link block.
- **The `` glyph depends on Nerd Fonts at render time.** On any machine without a Nerd Font mapped to the terminal profile, the statusline will show a box/question mark. Both Macs have Nerd Fonts installed via `helpers/install_fonts.sh`, so this should be fine — but if we ever render Claude Code in a non-Nerd-Font context (a shared tmux via SSH, say), the glyph will show as a question-mark tofu.
- **Branch color rule is name-based, not ref-based.** `master|main` match by string. A branch named `main-patch-1` would NOT match (that's correct — it's not a default). But if someone creates a branch called `master-v2` the intent is ambiguous. Accept the simplicity; fix if it ever trips someone.
- **The built-in PR badge on line 2 is not customizable.** The user's original ask was "display branch similarly to how PR shows" — the PR badge is Claude Code internal, line 2. We added branch to line 1 (the custom script), which is a different line entirely. Semantically equivalent (both are "repo context"), visually different (two lines). Accepted the mismatch.
- **Shared Forge learning about SOP dual-origin paths earned its keep three times in two days:** 2026-04-20 coined it, 2026-04-21 PR #44 round 1 caught Step 6, round 2 caught Step 5. The lesson is still: when migrating or copying ssh-based SOP commands, `grep -n "/home/node" <file>` first to catch siblings. One grep, every time.
- **Squash-merge convention held both PRs** (#44 and #45). master history shows one squash commit per PR, not the per-commit history from the branch.
