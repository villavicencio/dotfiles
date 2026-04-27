#!/usr/bin/env bash
# SessionStart hook — emits a fast, cheap orientation briefing on stdout
# so a fresh `claude` session has the same opening context the user would
# normally load by typing /pickup.
#
# Wired from claude/settings.json with matcher "startup" — fires only on
# fresh invocations, not on `--continue` (where context is already intact)
# or post-compaction. Output goes into the model's first-turn context as
# additionalContext (Claude Code injects all SessionStart hook stdout into
# the session). Cap is 10,000 chars total across all SessionStart hooks;
# this script targets <2,000 chars and <500ms wall clock so the heavier
# work stays behind explicit /pickup invocation.
#
# Repo-agnostic: every section guards on its prerequisites. Outside a git
# repo, with no HANDOFF.md, missing docs/ — the script still prints the
# header and any sections it can. Never errors, always exits 0; the worst
# case is an empty briefing, never a session-start failure.
#
# What's intentionally NOT here: the Forge bridge SSH call (~2-5s, ~48KB
# of output) and the VPS health snapshot. Both stay in claude/commands/
# pickup.md and run only when the user explicitly invokes /pickup. See
# docs/solutions/best-practices/claude-code-hooks-and-session-start-2026-04-27.md
# for the full design rationale.

set -u

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
  # Title + intro paragraph: everything before the first H2 heading.
  awk '/^## /{exit} {print}' HANDOFF.md
  # If a What's Next section exists, append it (until the next H2 or EOF).
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

print_trailer() {
  echo "For full orientation (Forge inbox, VPS health, synthesis), run /pickup."
}

print_header
print_handoff
print_git
print_ce_artifacts
print_trailer

exit 0
