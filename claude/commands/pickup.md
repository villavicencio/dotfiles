# /pickup — Pick Up Where We Left Off

Use this command at the start of a new session to get oriented fast.
Reads HANDOFF.md, loads relevant context, and tells you exactly where to start.

## Steps

### Step 1 — Read the handoff
```bash
cat HANDOFF.md 2>/dev/null || echo "No HANDOFF.md found."
```

If no HANDOFF.md exists, say so and fall back to git log:
```bash
git log --oneline -10
git status --short
```

### Step 2 — Load supporting context
```bash
export PATH="/Users/dvillavicencio/.config/nvm/versions/node/v24.13.0/bin:$PATH"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")

if [ -n "$REPO" ]; then
  echo "=== Open PRs ==="
  gh pr list --repo "$REPO" --state open --json number,title,headRefName,url
else
  echo "(No GitHub remote detected — skipping PR info)"
fi

echo "=== Current branch ==="
git branch --show-current

echo "=== Uncommitted changes ==="
git status --short
```

### Step 2b — Surface compound-engineering artifacts

Check for recent CE artifacts (brainstorms, plans, solutions) modified in the last 7 days.
These represent in-flight feature work and accumulated learnings that may be relevant.

```bash
echo "=== Recent brainstorms (last 7 days) ==="
find docs/brainstorms -name "*.md" -mtime -7 -exec basename {} \; 2>/dev/null | sort -r || echo "(none)"

echo "=== Recent plans (last 7 days) ==="
find docs/plans -name "*.md" -mtime -7 -exec basename {} \; 2>/dev/null | sort -r || echo "(none)"

echo "=== Recent solutions (last 7 days) ==="
find docs/solutions -name "*.md" -mtime -7 -exec basename {} \; 2>/dev/null | sort -r || echo "(none)"
```

If any artifacts are found:
- **Brainstorms** — mention them as open explorations that may need `/ce:plan` next
- **Plans** — mention them as ready for `/ce:work` (or already in progress)
- **Solutions** — briefly note what was learned (read the `problem_type` and `module` from YAML frontmatter if present)

### Step 2c — Forge bridge (if opted in)

Check if the project CLAUDE.md contains a `forge-project-key:` field. If not found, skip this step entirely.

If opted in, extract the project key value, then execute a **single SSH call** to read all Forge context:

```bash
# Replace {PROJECT_KEY} with the actual key from CLAUDE.md
# Note: use host volume path (not container path) since we SSH as root, not docker exec
VOLBASE="/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data"
ssh root@openclaw-prod "echo '===FORGE_SHARED===' && \
  cat $VOLBASE/workspace-forge/projects/_shared/*.md 2>/dev/null && \
  echo '===FORGE_PROJECT===' && \
  cat $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/*.md 2>/dev/null && \
  echo '===FORGE_INBOX===' && \
  ls $VOLBASE/shared/inbox/forge/ 2>/dev/null | grep -v '^archive$' && \
  echo '===FORGE_PENDING_TICKETS===' && \
  ls $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/ 2>/dev/null | grep -v '^done$'"
```

**If inbox files exist:**
1. Read each file's content (in the same or a follow-up SSH call)
2. Display the messages to the user under a "Messages for Forge:" header
3. Archive them: `mkdir -p $VOLBASE/shared/inbox/forge/archive && mv -n $VOLBASE/shared/inbox/forge/*.md $VOLBASE/shared/inbox/forge/archive/ 2>/dev/null`

**If pending ticket files exist:**
1. Read each ticket file's content
2. Display under a "Forge ticket requests:" header, showing title and description
3. Ask the user: "Create this ticket? (y/n)"
4. If approved, run the `/ticket` skill (or `gh issue create`) with the title and body from the file
5. After creation, move the file to `pending/done/`:
   ```bash
   ssh root@openclaw-prod "mkdir -p $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/done && \
     mv -n $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/{FILENAME} \
       $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/done/"
   ```

**If SSH fails:** Note "Forge bridge unavailable — using local context only" and continue. Do NOT block pickup.

**Also check for `.forge-pending`:** If a `.forge-pending` file exists in the project root (from a failed /handoff write-back), note it: "There are pending Forge write-backs from a previous session that failed to push."

Include the Forge context in your session synthesis (Step 3) — mention any cross-project patterns or messages from agents.

### Step 3 — Orient and propose next action

Synthesize everything into a brief, confident session kickoff:

1. **2-3 sentence summary** of where things stand — what was completed, what's in flight
2. **"Next up:"** — the single most important thing to tackle first, based on "What's Next" in the handoff
3. **CE artifacts** — if any brainstorms, plans, or solutions were found, note them briefly (e.g., "There's an open brainstorm on X ready for planning" or "2 new solutions were compounded last session")
4. **Any gotchas to keep in mind** — surface the watch-outs from the handoff so they're top of mind before touching code
5. **A ready-to-go prompt** — end with something like: *"Ready when you are — just say go and I'll start on [specific task]."*

Keep the tone direct and energized. This is a fresh start, not a status report.

## Notes
- If HANDOFF.md is stale (date is old), flag it: "This handoff is from X days ago — things may have moved."
- If there are open PRs with pending review comments, surface them — they're likely blocking
- Don't re-read CLAUDE.md or project docs unless the handoff references something that requires it
- The goal is: oriented and working within 60 seconds
