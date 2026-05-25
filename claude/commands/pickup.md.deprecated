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

**As of 2026-05-20, OpenClaw is destroyed and Hermes-Atlas is the live runtime.** This step snapshots Hermes + Axiom + host health instead of the (defunct) OpenClaw container. See `docs/plans/2026-05-20-001-chore-destroy-openclaw-record.md` in the openclaw repo for the full transition.

This step is defensive — it catches classes of failure that HANDOFF.md doesn't (cron-delivery errors that silently swallow output, scheduler crashes, Hermes-gateway restarts, sustained SSH bruteforce). Without it, the session can go several turns before you notice that the VPS has been degraded the whole time.

Run this **single SSH call** and include the resulting headline in your Step 3 synthesis:

```bash
ssh root@openclaw-prod '
  echo "===HERMES_GATEWAY==="
  systemctl is-active hermes-gateway.service 2>&1
  systemctl show hermes-gateway.service --property=NRestarts,ActiveEnterTimestamp,MainPID 2>&1 | tr "\n" " " | head -c 300; echo

  echo "===HERMES_CRON_STATUS==="
  sudo -u node bash -lc "hermes cron status 2>&1" | head -10

  echo "===HERMES_CRON_FAILURES_24H==="
  sudo -u node python3 -c "
import json, datetime
data = json.load(open(\"/home/node/.hermes/cron/jobs.json\"))
now = datetime.datetime.now(datetime.timezone.utc)
cutoff = now - datetime.timedelta(hours=24)
issues = []
for j in data.get(\"jobs\", []):
    last_status = j.get(\"last_status\")
    last_run = j.get(\"last_run_at\")
    last_err = j.get(\"last_error\")
    deliv_err = j.get(\"last_delivery_error\")
    if last_run:
        try:
            t = datetime.datetime.fromisoformat(last_run.replace(\"Z\",\"+00:00\"))
            if t >= cutoff and (last_status != \"ok\" or deliv_err):
                issues.append(f\"  {j[\"id\"][:12]:12s} {j[\"name\"][:40]:40s} status={last_status} err={last_err or deliv_err}\")
        except Exception: pass
print(\"\n\".join(issues) if issues else \"(no cron failures in past 24h)\")
" 2>&1

  echo "===AXIOM_TMUX==="
  systemctl is-active axiom-tmux.service 2>&1
  sudo -u axiom tmux ls 2>&1 | head -3

  echo "===HOST_MEMORY==="
  free -h | head -3

  echo "===HOST_LOAD==="
  uptime

  echo "===HERMES_FEED_FRESHNESS==="
  for d in doc-health ben-digest wire-signals volo-gaming borges-library; do
    latest=$(sudo -u node ls -t /home/node/.hermes/feeds/$d/*.md 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      age=$(stat -c %Y "$latest" 2>/dev/null)
      now=$(date +%s)
      hours_ago=$(( (now - age) / 3600 ))
      printf "  %-15s last write %3dh ago  %s\n" "$d" "$hours_ago" "$(basename $latest)"
    else
      printf "  %-15s (no files)\n" "$d"
    fi
  done

  echo "===SSH_BRUTEFORCE_PRESSURE==="
  journalctl -u ssh --since "1 hour ago" --no-pager 2>/dev/null | grep -cE "Failed password|Invalid user" | awk "{ print \$1, \"failed-auth events in past 1h\" }"
  echo "===FAIL2BAN_JAIL_STATUS==="
  command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client status sshd 2>/dev/null | grep -E "Currently failed|Currently banned|Total banned" || echo "(fail2ban not installed)"

  echo "===OC_VOLUME_INTACT==="
  test -f /var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data/openclaw.json && echo "ok (cold backup present)" || echo "MISSING — cold backup gone"
'
```

Treat each section independently — empty sections are load-bearing. Never skip past one silently.

**Interpretation rules:**

- **`HERMES_GATEWAY` not `active`** — Hermes-Atlas is down. This is critical; surface as the headline before anything else. Restart via `sudo systemctl restart hermes-gateway.service`.
- **`HERMES_CRON_STATUS` shows scheduler not running** — crons won't fire. Same severity as gateway down.
- **`HERMES_CRON_FAILURES_24H` lists ANY job** — surface them. The output includes both agent errors (`last_error`) and delivery errors (`last_delivery_error` — Telegram down, etc.). Delivery errors are the classic silent-failure mode the user actually cares about.
- **`AXIOM_TMUX` not `active`** — Axiom is down. Restart via `sudo systemctl restart axiom-tmux.service`.
- **`HERMES_FEED_FRESHNESS` showing a daily feed > 30h** — that cron silently failed to deliver. Cross-reference with `HERMES_CRON_FAILURES_24H`. Daily feeds: `doc-health` (7am PT), `ben-digest` (10pm PT), `wire-signals` (3pm PT). Weekly: `volo-gaming` (Sun 11am), `borges-library` (Sun 10am). Note: `bill-audit` cron exists but delivers via Telegram only — no local feed dir to track.
- **`OC_VOLUME_INTACT` missing** — the cold backup is gone. Surface immediately; the rebuild reference is the volume, so losing it changes the rebuild story dramatically.
- **SSH brute-force pressure** — informational unless fail2ban is at 0 banned + pressure is sustained over multiple `/pickup` calls.

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
