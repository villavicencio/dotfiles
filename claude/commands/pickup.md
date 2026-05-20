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
export PATH="$HOME/.config/nvm/versions/node/v24.13.0/bin:$PATH"

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

### Step 2c — VPS health snapshot (openclaw-prod projects)

Skip this step unless this project targets `openclaw-prod`. Detect via git remote:

```bash
git remote -v 2>/dev/null | grep -q "openclaw" || { echo "(not an openclaw-prod project — skipping VPS health snapshot)"; }
```

If the remote doesn't contain "openclaw", skip entirely. Other projects run on different infrastructure.

This step is defensive — it catches classes of failure that HANDOFF.md doesn't (security audit findings, silent OOM regressions, runaway restart loops, perm drift). Without it, the session can go several turns before you notice that the VPS has been degraded the whole time — exactly what happened on 2026-04-14.

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
  echo "===HANDOFF_STALENESS==="
  find /var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data -mindepth 2 -maxdepth 2 -name "HANDOFF.md" -mtime +7 -printf "%TY-%Tm-%Td %p\n" 2>/dev/null
  echo "===HOST_LOAD==="
  uptime
  echo "===SSH_BRUTEFORCE_PRESSURE==="
  journalctl -u ssh --since "1 hour ago" --no-pager 2>/dev/null | grep -cE "Failed password|Invalid user" | awk "{ print \$1, \"failed-auth events in past 1h\" }"
  echo "===FAIL2BAN_JAIL_STATUS==="
  command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client status sshd 2>/dev/null | grep -E "Currently failed|Currently banned|Total banned" || echo "(fail2ban not installed)"
'
```

Treat each section independently — empty sections are load-bearing. Never skip past one silently.

**Interpretation rules:**

- **Status lines starting with `CRITICAL` or `ERROR` in the `openclaw status --deep` output** — surface these prominently in Step 3. Catching them at session start saves a round-trip.
- **`RestartCount > 0` or `OOMKilled: true`** — the container has crashed since the handoff was written. Flag it; the session is starting against a degraded baseline.
- **`memory.current` > 70% of `memory.max`** — gateway is close to its cgroup ceiling right now, not hours from now. If your workload for this session is heavy (multiple `/ce:compound` rounds, agent spawns), consider a graceful restart before starting work.
- **OOM events in past 24h > 0** — there's a regression in progress. Escalate to "what changed recently" as the first order of business.
- **Perm-drift alerts present** — the daily perm-drift check cron (host-level, writes to `shared/inbox/forge/` because that path predates the Forge bridge deprecation) caught something. Read the alert file and remediate before other work.
- **HANDOFF_STALENESS lists ANY workspace HANDOFF.md older than 7 days** — agent-side `/handoff` hasn't fired for that agent in over a week. Mostly informational post-fold-and-collapse since most workspaces are now archived; surface only if it's an actively-used workspace (`workspace/` for Atlas-on-OpenClaw is the main remaining one).

If SSH fails: note "VPS health snapshot unavailable" and continue; do not block pickup. Rationale: a down VPS is important information, but a Mac-side `/pickup` shouldn't stall on network problems.

### Step 3 — Orient and propose next action

Synthesize everything into a brief, confident session kickoff:

1. **2-3 sentence summary** of where things stand — what was completed, what's in flight
2. **VPS health headline** (if Step 2c ran) — one line: *"VPS clean"* if all checks passed, or the most urgent finding if not (critical audit finding, OOM regression, restart loop, perm drift)
3. **"Next up:"** — the single most important thing to tackle first, based on "What's Next" in the handoff; bump it below a VPS escalation if 2c surfaced one
4. **CE artifacts** — if any brainstorms, plans, or solutions were found, note them briefly (e.g., "There's an open brainstorm on X ready for planning" or "2 new solutions were compounded last session")
5. **Any gotchas to keep in mind** — surface the watch-outs from the handoff so they're top of mind before touching code
6. **A ready-to-go prompt** — end with something like: *"Ready when you are — just say go and I'll start on [specific task]."*

Keep the tone direct and energized. This is a fresh start, not a status report.

## Notes
- If HANDOFF.md is stale (date is old), flag it: "This handoff is from X days ago — things may have moved."
- If there are open PRs with pending review comments, surface them — they're likely blocking
- Don't re-read CLAUDE.md or project docs unless the handoff references something that requires it
- The goal is: oriented and working within 60 seconds
