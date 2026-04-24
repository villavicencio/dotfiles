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
# Use `find -maxdepth 1 -type f` (NOT `ls | grep -v`) to list drops — it skips
# sibling directories like `archive/` and `done/` by type rather than by name,
# and behaves predictably inside nested SSH quoting. Silent drops here = missed tickets.
VOLBASE="/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data"
ssh root@openclaw-prod "echo '===FORGE_SHARED===' && \
  cat $VOLBASE/workspace-forge/projects/_shared/*.md 2>/dev/null && \
  echo '===FORGE_PROJECT===' && \
  cat $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/*.md 2>/dev/null && \
  echo '===FORGE_INBOX===' && \
  find $VOLBASE/shared/inbox/forge -maxdepth 1 -type f -name '*.md' -printf '%f\n' 2>/dev/null && \
  echo '===FORGE_PENDING_TICKETS===' && \
  find $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending -maxdepth 1 -type f -name 'ticket-*.md' -printf '%f\n' 2>/dev/null"
```

**Verify the output.** The two list sections (`FORGE_INBOX`, `FORGE_PENDING_TICKETS`) must be treated as load-bearing. If either is empty, state that explicitly in your summary (*"No pending tickets"*). Never skip past an empty section silently — a bug that swallows ticket filenames will look identical to a genuinely empty queue, and silent drops are how missed tickets happen.

**If inbox files exist:**
1. Read each file's content (in the same or a follow-up SSH call)
2. Display the messages to the user under a "Messages for Forge:" header
3. Archive them (trailing `chown` keeps the archive subtree writable by the container node user — see dotfiles#47/#50):
   ```bash
   # Uses `find ... -exec mv -t DEST {} +` (plus form, not `\;`): empty inbox
   # is a natural no-op (exit 0), a real mv failure propagates to find's exit,
   # and the outer && chain only runs chown if everything above succeeded.
   # The `\;` form silently discards mv's exit code — use `+` here.
   ssh root@openclaw-prod "mkdir -p $VOLBASE/shared/inbox/forge/archive && \
     find $VOLBASE/shared/inbox/forge -maxdepth 1 -type f -name '*.md' \
       -exec mv -n -t $VOLBASE/shared/inbox/forge/archive/ {} + && \
     chown -R 1000:1000 $VOLBASE/shared/inbox/forge/archive"
   ```

**If pending ticket files exist:**
1. Read each ticket file's content
2. Display under a "Forge ticket requests:" header, showing title and description
3. Ask the user: "Create this ticket? (y/n)"
4. If approved, run the `/ticket` skill (or `gh issue create`) with the title and body from the file
5. After creation, move the file to `pending/done/`:
   ```bash
   # Trailing chown keeps pending/done/ writable by the container node user
   # (uid 1000). ssh-as-root mkdir + mv otherwise creates a root-owned `done/`
   # that Forge cannot manage from inside the container. See dotfiles#47/#50.
   ssh root@openclaw-prod "mkdir -p $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/done && \
     mv -n $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/{FILENAME} \
       $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/done/ && \
     chown -R 1000:1000 $VOLBASE/workspace-forge/projects/{PROJECT_KEY}/pending/done"
   ```

**If SSH fails:** Note "Forge bridge unavailable — using local context only" and continue. Do NOT block pickup.

**Also check for `.forge-pending`:** If a `.forge-pending` file exists in the project root (from a failed /handoff write-back), note it: "There are pending Forge write-backs from a previous session that failed to push."

Include the Forge context in your session synthesis (Step 3) — mention any cross-project patterns or messages from agents.

### Step 2d — VPS health snapshot (only when `forge-project-key: openclaw-forge`)

Skip this step unless the project CLAUDE.md declares `forge-project-key: openclaw-forge`. Other Forge projects run on different infrastructure.

This step is defensive — it catches classes of failure that HANDOFF.md and Forge inbox don't (security audit findings that haven't been landed as tickets yet, silent OOM regressions, runaway restart loops). Without it, the session can go several turns before you notice that the VPS has been degraded the whole time — exactly what happened on 2026-04-14.

Run this **single SSH call** and include the resulting headline in your Step 3 synthesis:

```bash
ssh root@openclaw-prod '
  echo "===OPENCLAW_STATUS_DEEP==="
  docker exec openclaw-d95veq7chb3d8gllyj6vhpqy sh -c "openclaw status --deep 2>&1" 2>/dev/null | head -60
  echo "===HOST_MEMORY==="
  free -h | head -3
  echo "===CONTAINER_CGROUP==="
  CID=$(docker inspect openclaw-d95veq7chb3d8gllyj6vhpqy --format "{{.Id}}" 2>/dev/null)
  if [ -n "$CID" ]; then
    cat /sys/fs/cgroup/system.slice/docker-$CID.scope/memory.current 2>/dev/null | awk "{ printf \"memory.current: %.2f MB\n\", \$1/1024/1024 }"
    cat /sys/fs/cgroup/system.slice/docker-$CID.scope/memory.max 2>/dev/null | awk "{ printf \"memory.max:     %.2f MB\n\", \$1/1024/1024 }"
    cat /sys/fs/cgroup/system.slice/docker-$CID.scope/memory.swap.current 2>/dev/null | awk "{ printf \"swap.current:   %.2f MB\n\", \$1/1024/1024 }"
    docker inspect openclaw-d95veq7chb3d8gllyj6vhpqy --format "RestartCount: {{.RestartCount}} | OOMKilled: {{.State.OOMKilled}} | Status: {{.State.Status}} | StartedAt: {{.State.StartedAt}}" 2>/dev/null
  fi
  echo "===OOM_LAST_24H==="
  journalctl -k --since "24 hours ago" --no-pager 2>/dev/null | grep -c "oom-kill:constraint" | awk "{ print \$1, \"OOM events in past 24h\" }"
  echo "===PERM_DRIFT_ALERTS==="
  find /var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/shared/inbox/forge -maxdepth 1 -type f -name "*perm-drift*.md" 2>/dev/null | head -3
'
```

Treat each section independently — empty sections are load-bearing, same rule as 2c. Never skip past one silently.

**Interpretation rules:**

- **Status lines starting with `CRITICAL` or `ERROR` in the `openclaw status --deep` output** — surface these prominently in Step 3. These are the exact class of thing that becomes Forge tickets the next day. Catching them at session start saves a round-trip.
- **`RestartCount > 0` or `OOMKilled: true`** — the container has crashed since the handoff was written. Flag it; the session is starting against a degraded baseline.
- **`memory.current` > 70% of `memory.max`** — gateway is close to its cgroup ceiling right now, not hours from now. If your workload for this session is heavy (multiple `/ce:compound` rounds, agent spawns), consider a graceful restart before starting work.
- **OOM events in past 24h > 0** — there's a regression in progress. Escalate to "what changed recently" as the first order of business.
- **Perm-drift alerts present** — the daily perm-drift check cron caught something. Read the alert file and remediate before other work.

If SSH fails: note "VPS health snapshot unavailable" and continue; do not block pickup. Rationale: a down VPS is important information, but a Mac-side `/pickup` shouldn't stall on network problems.

### Step 3 — Orient and propose next action

Synthesize everything into a brief, confident session kickoff:

1. **2-3 sentence summary** of where things stand — what was completed, what's in flight
2. **VPS health headline** (if Step 2d ran) — one line: *"VPS clean"* if all checks passed, or the most urgent finding if not (critical audit finding, OOM regression, restart loop, perm drift)
3. **"Next up:"** — the single most important thing to tackle first, based on "What's Next" in the handoff; bump it below a VPS escalation if 2d surfaced one
4. **CE artifacts** — if any brainstorms, plans, or solutions were found, note them briefly (e.g., "There's an open brainstorm on X ready for planning" or "2 new solutions were compounded last session")
5. **Any gotchas to keep in mind** — surface the watch-outs from the handoff so they're top of mind before touching code
6. **A ready-to-go prompt** — end with something like: *"Ready when you are — just say go and I'll start on [specific task]."*

Keep the tone direct and energized. This is a fresh start, not a status report.

## Notes
- If HANDOFF.md is stale (date is old), flag it: "This handoff is from X days ago — things may have moved."
- If there are open PRs with pending review comments, surface them — they're likely blocking
- Don't re-read CLAUDE.md or project docs unless the handoff references something that requires it
- The goal is: oriented and working within 60 seconds
