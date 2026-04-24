# /handoff — Generate Session Handoff Doc

Use this command at the end of any working session to write `HANDOFF.md` at the repo root.
Captures what was built, decisions made, what's next, and gotchas — so the next session
(yours or a teammate's) can `/pickup` and be working within 60 seconds.

Optionally scope it: `/handoff hero section` or `/handoff PR 28 work`.

## Steps

### Step 1 — Gather context
```bash
export PATH="/Users/dvillavicencio/.config/nvm/versions/node/v24.13.0/bin:$PATH"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")

echo "=== Commits this session (branch vs main) ==="
git log main..HEAD --oneline 2>/dev/null || git log --oneline -10

if [ -n "$REPO" ]; then
  echo "=== Recently merged PRs (last 5) ==="
  gh pr list --repo "$REPO" --state merged --limit 5 --json number,title,mergedAt

  echo "=== Open PRs ==="
  gh pr list --repo "$REPO" --state open --json number,title,headRefName,url

  echo "=== Open PR review comments (first open PR) ==="
  OPEN_PR=$(gh pr list --repo "$REPO" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$OPEN_PR" ]; then
    gh pr view $OPEN_PR --repo "$REPO" --comments 2>/dev/null | tail -40
  fi
else
  echo "(No GitHub remote detected — skipping PR info)"
fi

echo "=== Uncommitted changes ==="
git status --short
```

### Step 2 — Write HANDOFF.md

Using everything from this session plus the gathered context, write `HANDOFF.md`:

```markdown
# HANDOFF — [YYYY-MM-DD, time of day]

## What We Built
[Concrete bullet list — PRs opened/merged, components changed, bugs fixed, docs added.
Name the files, PR numbers, and components. "Fixed hero clip-path" is weak. "PR #28 — tuned
ellipse(80% 56%) dome, reduced top padding pt-20→pt-6, moved brand label below subtitle" is good.]

## Decisions Made
[Architectural, design, or implementation calls and the reasoning behind them.
If a CLAUDE.md rule was added or updated, note it here.
If something was explicitly ruled out, say so and why — saves the next session from relitigating it.]

## What Didn't Work
[Approaches that failed, dead ends, or things explicitly ruled out — so the next session
doesn't relitigate or retry them. Include why they failed when known.]

## What's Next
[Prioritized list. Lead with the single most important thing.
Be specific: name the file, PR, or component. Vague summaries don't help the next session.]

## Gotchas & Watch-outs
[Anything that bit us, workarounds in place, known fragile spots, or things to check before
touching related code. When in doubt, over-document here.]
```

**Quality bar:** Every bullet should be specific enough that someone who wasn't in this session
knows exactly what happened and what to do next. No vague summaries.

### Step 3 — Check for blockers
Before confirming, scan for anything that would block the next session and call it out explicitly if found:
- Open PR with unresolved review comments → list them
- Uncommitted changes that should be stashed or committed first
- A decision that's still open / needs input from someone else

### Step 4 — Confirm
After writing, reply with:
- "✅ HANDOFF.md written."
- A 2-sentence plain-English summary of session state — what shipped and what's in flight
- If there are immediate blockers: "⚠️ Before next session: [specific thing]"

### Step 5 — Forge write-back (if opted in)

Check if the project CLAUDE.md contains a `forge-project-key:` field. If not found, skip this step entirely.

If opted in:

1. **Analyze the session** for durable learnings worth pushing to Forge:
   - Cross-project patterns (e.g., "always batch SSH calls for performance") → candidate for `_shared/patterns.md`
   - Project-specific decisions or architecture notes → candidate for `{project-key}/context.md`
   - Universal preferences or tool tips → candidate for `_shared/preferences.md`
   - Keep each entry concise — under 200 tokens (nano-friendly)

2. **Present candidates** to the user for approval:
   ```
   Push to Forge? [_shared/patterns.md]: "Batch multiple SSH reads into a single call — saves 2-4s per pickup"
   ```
   The user approves or rejects each item individually.

3. **For approved items**, append via SSH using **safe stdin pipe** (NEVER use echo with interpolation). All paths below use the host-volume root (`/var/lib/docker/volumes/<volume>/_data/…`), same convention as `/pickup` Step 2c — these commands run over plain SSH, not `docker exec`, so the container-internal `/home/node/...` path would silently create a shadow tree the bridge never reads (see shared Forge learning 2026-04-20):
   ```bash
   # Trailing chown keeps the file writable by the container node user (uid 1000).
   # ssh-as-root + `>>` creates absent files as root on first write, locking Forge
   # out of subsequent in-container updates. See dotfiles#47.
   printf '%s\n' "- [YYYY-MM-DD] LEARNING_TEXT" | ssh root@openclaw-prod 'DEST=/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/workspace-forge/projects/{TARGET_FILE}; cat >> "$DEST"; chown 1000:1000 "$DEST"'
   ```

4. **If SSH fails**, save approved items to `.forge-pending` in the project root as JSON-lines:
   ```
   {"target": "_shared/patterns.md", "content": "Batch SSH calls for performance", "date": "2026-04-12"}
   ```
   Next `/handoff` or `/pickup` will detect this file and retry.

5. **Log the sync** to shared/comms for audit trail:
   ```bash
   # Trailing chown keeps the comms log writable by the container node user
   # (uid 1000). Same first-write ownership trap as Step 5/6 — see dotfiles#47/#50.
   printf '%s\n' "[Forge bridge] Synced N items from {project-key} session" | ssh root@openclaw-prod 'DEST=/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/shared/comms/YYYY-MM-DD.md; cat >> "$DEST"; chown 1000:1000 "$DEST"'
   ```

If there are no durable learnings worth pushing, skip silently — not every session produces cross-project knowledge.

### Step 6 — Append cadence briefing to Forge's project folder (if Forge-enabled)

This step runs only for Forge-enabled projects (same `forge-project-key:` gate as Step 5). Skip if no key found.

After the handoff is written and Forge write-back is done (or skipped), append a concise session briefing to Forge's per-project memory so the cadence-tracking role persists across sessions. This replaces the old Perry-briefing flow — Perry was retired 2026-04-20 and Forge absorbed the cadence role.

1. **Compose the briefing** from HANDOFF.md — include:
   - What shipped this session (1-3 bullet points, specific)
   - What's next (top 1-2 priorities)
   - Any decisions that affect scope, timeline, or other agents
   - Any new tickets created

   Keep it under 250 words. This is a signal-only log, not narration.
   **Always lead with a timestamp and the project key** so the cadence log stays scannable (e.g., "## 2026-04-20 — openclaw-forge session briefing").

2. **Append to the Forge project cadence log:**
   ```bash
   # Host-volume path — same root /pickup reads from (Step 2c). Do NOT use
   # /home/node/.openclaw/... here: that is the container-internal path
   # and this command runs over plain SSH on the host, not docker exec.
   # Using the container path silently creates a shadow tree that /pickup
   # never reads. See shared Forge learning 2026-04-20 "SOP commands that
   # reference /home/node/... are container-internal paths".
   VOLBASE=/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data
   # Trailing chown keeps cadence-log.md writable by the container node user (uid 1000).
   # ssh-as-root + `>>` creates absent files as root on first write, locking Forge
   # out of subsequent in-container updates. See dotfiles#47.
   ssh root@openclaw-prod "DEST=$VOLBASE/workspace-forge/projects/{PROJECT_KEY}/cadence-log.md; mkdir -p \"\$(dirname \"\$DEST\")\"; { echo ''; cat; } >> \"\$DEST\"; chown 1000:1000 \"\$DEST\"" <<'EOF'
   ## YYYY-MM-DD — {PROJECT_KEY} session briefing
   SESSION_BRIEFING_HERE
   EOF
   ```
   Replace `{PROJECT_KEY}` with the actual forge-project-key from CLAUDE.md. This gives Forge a chronological record of what shipped on each project across sessions, which he can surface when asked for a cadence read ("what moved recently?", "where are we on X?").

3. **If the append fails** (disk full, permissions, SSH error), note the failure and continue. Don't block the handoff. The HANDOFF.md itself still captures the same content; the cadence log is an accumulation artifact.

## Notes
- Overwrites existing HANDOFF.md — it's always current-session state, not a history log
- Commits the file automatically if there are no other uncommitted changes:
  ```bash
  git add HANDOFF.md && git commit -m "docs: update handoff"
  git remote | grep -q . && git push || echo "(no remote — skipping push)"
  ```
  If there ARE other uncommitted changes, skip the commit and note it in the confirmation.
- Pairs with `/pickup` — the next session starts there
