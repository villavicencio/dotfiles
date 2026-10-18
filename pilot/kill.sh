#!/bin/sh
# hal pilot kill switch (VIL-396). Run as david on hal:
#   ~/Projects/Personal/dotfiles/pilot/kill.sh        # stop now, stay off
#   ~/Projects/Personal/dotfiles/pilot/kill.sh --on   # allow runs again
# It creates ~/runs/DISABLED, which every gate checks, and kills a running
# runner's process group (the planner or worker included). It does NOT unload
# any LM Studio model: Atlas and Axiom use both (VIL-395).
RUNS="${PILOT_RUNS:-$HOME/runs}"
if [ "${1:-}" = "--on" ]; then
  rm -f "$RUNS/DISABLED" && echo "pilot: enabled (DISABLED removed)"
  exit 0
fi
mkdir -p "$RUNS" && date > "$RUNS/DISABLED"
echo "pilot: disabled ($RUNS/DISABLED)"
pid=$(cat "$RUNS/runner.pid" 2>/dev/null)
# The runner removes runner.pid on exit; a leftover one could name a reused
# PID, so signal it only if that process is still runner.py.
cmd=$(ps -p "${pid:-0}" -o command= 2>/dev/null)
if [ -n "$pid" ] && case "$cmd" in *pilot/runner.py*) true ;; *) false ;; esac; then
  # The planner and worker run in their own process groups (start_new_session),
  # so kill those first, then the runner.
  for child in $(pgrep -P "$pid"); do kill -TERM -- "-$child" 2>/dev/null; done
  kill -TERM "$pid" && echo "pilot: stopped runner $pid and its children"
else
  echo "pilot: no runner running"
fi
