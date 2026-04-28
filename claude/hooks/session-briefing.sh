#!/usr/bin/env bash
# SessionStart hook — emits an orientation briefing on stdout so a fresh
# `claude` session has the same opening context the user would normally
# load by typing /pickup.
#
# Wired from claude/settings.json with matcher "startup". Output goes into
# the model's first-turn context as additionalContext (Claude Code injects
# all SessionStart hook stdout into the session). The 10,000-character cap
# is the hard ceiling; this script slices intelligently to stay under
# ~9,500 chars even in the worst case (busy Forge inbox + pending tickets).
#
# Sections, in order:
#   - Header marker
#   - HANDOFF.md slice (title + intro + What's Next)
#   - Git context (branch, uncommitted count)
#   - Recent CE artifact counts (docs/{brainstorms,plans,solutions}/)
#   - Forge bridge — when cwd's CLAUDE.md has `forge-project-key:`:
#       * tail of _shared/patterns.md (recent cross-project learnings)
#       * tail of project cadence-log (recent session briefings)
#       * inbox messages (full content, capped at 2 files + "N more" hint)
#       * pending tickets (full content, capped at 2 files + "N more" hint)
#   - Trailer pointing at /pickup for actions (archival, ticket promotion,
#     full synthesis) the briefing alone cannot perform
#   - Self-truncation footer if total output exceeds the budget
#
# Repo-agnostic: every section guards on its prerequisites and the worst
# case is an empty briefing, never a session-start failure. SSH timeouts
# and unreachable Forge bridge degrade to a one-line note. Always exits 0.
#
# Forge bridge mirrors claude/commands/pickup.md Step 2c (single SSH call,
# delimited blocks). What it does NOT do: the inbox archival mv, the
# pending-ticket promotion to GH issues, the VPS health snapshot. Those
# are interactive or destructive and stay behind explicit /pickup. See
# docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md
# for the design rationale and the duplicate-vs-hint tradeoff.

set -u

# Output budget — when the accumulated stdout approaches this, we truncate
# with a footer pointing at /pickup. 9500 leaves headroom under the harness's
# 10,000-char additionalContext cap.
BUDGET=9500

print_header() {
  echo "=== Session briefing ==="
  echo
}

print_handoff() {
  if [ ! -f HANDOFF.md ]; then
    echo "HANDOFF.md: not present in $(pwd)"
    echo
    return
  fi

  echo "HANDOFF.md (title + intro + What's Next):"
  echo "---"
  awk '/^## /{exit} {print}' HANDOFF.md
  if grep -q '^## What.s Next' HANDOFF.md; then
    echo "..."
    awk '/^## What.s Next/{flag=1; print; next} flag && /^## /{exit} flag{print}' HANDOFF.md
  fi
  echo "---"
  echo
}

print_git() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  local branch dirty_count
  branch=$(git branch --show-current 2>/dev/null || echo "(detached)")
  dirty_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  echo "Git: branch=${branch}, uncommitted=${dirty_count} files"
  echo
}

print_ce_artifacts() {
  local found_any=0
  for dir in docs/brainstorms docs/plans docs/solutions; do
    if [ -d "$dir" ]; then
      local count
      count=$(find "$dir" -name '*.md' -mtime -7 2>/dev/null | wc -l | tr -d ' ')
      if [ "$found_any" -eq 0 ]; then
        echo "Recent CE artifacts (last 7 days):"
        found_any=1
      fi
      echo "  ${dir}: ${count} file(s)"
    fi
  done
  [ "$found_any" -eq 1 ] && echo
}

print_forge_bridge() {
  # Gate: only fire in projects that opt in via CLAUDE.md.
  if [ ! -f CLAUDE.md ]; then
    return
  fi
  local project_key
  project_key=$(grep -E '^forge-project-key:' CLAUDE.md 2>/dev/null \
    | head -1 \
    | sed 's/^forge-project-key:[[:space:]]*//' \
    | tr -d '[:space:]')
  if [ -z "$project_key" ]; then
    return
  fi

  echo "Forge bridge (project=${project_key}):"

  local output exit_code
  # Single SSH call, body sent via heredoc to avoid local/remote quoting hell.
  # Project key is passed as $1 to remote bash. ConnectTimeout=3 caps connection
  # time; the harness `timeout: 10` in settings.json is the overall safety net.
  output=$(ssh -o ConnectTimeout=3 -o BatchMode=yes \
    root@openclaw-prod bash -s -- "$project_key" 2>&1 << 'REMOTE'
P="$1"
V="/var/lib/docker/volumes/d95veq7chb3d8gllyj6vhpqy_openclaw-state/_data"

echo "--- _shared/patterns.md (last 8 lines) ---"
tail -n 8 "$V/workspace-forge/projects/_shared/patterns.md" 2>/dev/null

echo
echo "--- $P cadence-log (last 20 lines) ---"
tail -n 20 "$V/workspace-forge/projects/$P/cadence-log.md" 2>/dev/null

echo
echo "--- Inbox messages ---"
INBOX_FILES=()
while IFS= read -r f; do INBOX_FILES+=("$f"); done < <(find "$V/shared/inbox/forge" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
INBOX_N=${#INBOX_FILES[@]}
echo "($INBOX_N message(s))"
i=0
for f in "${INBOX_FILES[@]}"; do
  if [ "$i" -ge 2 ]; then
    echo
    echo "(... $((INBOX_N - 2)) more — run /pickup for full list)"
    break
  fi
  echo
  echo "=== $(basename "$f") ==="
  head -20 "$f"
  i=$((i + 1))
done

echo
echo "--- Pending tickets ---"
PEND_FILES=()
while IFS= read -r f; do PEND_FILES+=("$f"); done < <(find "$V/workspace-forge/projects/$P/pending" -maxdepth 1 -type f -name 'ticket-*.md' 2>/dev/null | sort)
PEND_N=${#PEND_FILES[@]}
echo "($PEND_N pending)"
i=0
for f in "${PEND_FILES[@]}"; do
  if [ "$i" -ge 2 ]; then
    echo
    echo "(... $((PEND_N - 2)) more — run /pickup for full list)"
    break
  fi
  echo
  echo "=== $(basename "$f") ==="
  head -20 "$f"
  i=$((i + 1))
done
REMOTE
)
  exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  (Forge bridge unreachable — SSH failed, timed out, or permission denied)"
    echo
    return
  fi

  echo "$output"
  echo
}

print_trailer() {
  echo "For inbox archival, ticket promotion, or full /pickup synthesis, run /pickup."
}

# Capture all output, then check size and truncate if needed.
output=$(
  print_header
  print_handoff
  print_git
  print_ce_artifacts
  print_forge_bridge
  print_trailer
)

byte_count=${#output}
if [ "$byte_count" -gt "$BUDGET" ]; then
  # Truncate to the last whole line under budget, then append a footer.
  printf '%s' "$output" | head -c "$BUDGET"
  echo
  echo "..."
  echo "(briefing truncated at ${BUDGET} chars — run /pickup for full output)"
else
  printf '%s\n' "$output"
fi

exit 0
