#!/bin/sh
# herdr-blank-state.sh — show "blank" in herdr's agent sidebar for a
# context-free Claude Code pane.
#
# Claude Code's SessionStart hook reports how the session began:
#   startup  fresh launch, no context      -> blank
#   clear    /clear was run, no context    -> blank
#   resume   --resume/--continue, has hist -> NOT blank
#   compact  post-compaction, has context  -> NOT blank
#
# On a blank start we set herdr's display-only `state_labels` override so the
# `state_text` row renders "blank" instead of "idle". UserPromptSubmit clears
# it — the first prompt is what makes the pane non-blank.
#
# Deliberately writes the socket directly rather than shelling out to `herdr`:
# no PATH dependency, one fewer process, and it mirrors herdr's own
# integration hook (~/.claude/hooks/herdr-agent-state.sh).
#
# NOTE: SessionStart and UserPromptSubmit both inject hook stdout into the
# model's context. This hook must stay silent on stdout and always exit 0.

set -eu

# Which SessionStart sources count as blank. Edit this list to change the rule.
BLANK_SOURCES="startup clear"

# Safety net: if a clear is ever missed, the label expires on its own rather
# than pinning a pane at "blank" forever. 12h.
BLANK_TTL_MS=43200000

action="${1:-}"
case "$action" in
  start|clear) ;;
  *) exit 0 ;;
esac

# Not inside a herdr pane -> nothing to report.
[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-blank-hook.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

HERDR_ACTION="$action" \
HERDR_HOOK_INPUT_FILE="$hook_input_file" \
HERDR_BLANK_SOURCES="$BLANK_SOURCES" \
HERDR_BLANK_TTL_MS="$BLANK_TTL_MS" \
python3 - <<'PY' >/dev/null 2>&1 || true
import json
import os
import socket
import time

action = os.environ.get("HERDR_ACTION", "")
pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
hook_input_file = os.environ.get("HERDR_HOOK_INPUT_FILE")
blank_sources = set(os.environ.get("HERDR_BLANK_SOURCES", "").split())
try:
    ttl_ms = int(os.environ.get("HERDR_BLANK_TTL_MS", "43200000"))
except ValueError:
    ttl_ms = 43200000

if not pane_id or not socket_path:
    raise SystemExit(0)

hook_input = {}
if hook_input_file:
    try:
        with open(hook_input_file, encoding="utf-8") as handle:
            content = handle.read()
        if content.strip():
            hook_input = json.loads(content)
    except Exception:
        hook_input = {}

# Subagents share the pane but are not the pane's session; ignore them.
if hook_input.get("agent_id"):
    raise SystemExit(0)

params = {
    "pane_id": pane_id,
    "source": "dotfiles:blank-state",
    "seq": time.time_ns(),
}

if action == "start":
    source = hook_input.get("source")
    if not isinstance(source, str) or source not in blank_sources:
        # resume / compact / anything unrecognized: the pane has context.
        # Clear rather than no-op, so a resume over a blank pane corrects it.
        params["clear_state_labels"] = True
    else:
        params["state_labels"] = {"idle": "blank"}
        params["ttl_ms"] = ttl_ms
else:  # clear — the first prompt means the pane is no longer blank
    params["clear_state_labels"] = True

request = {
    "id": "dotfiles:blank-state:%d" % time.time_ns(),
    "method": "pane.report_metadata",
    "params": params,
}

try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    client.connect(socket_path)
    client.sendall((json.dumps(request) + "\n").encode())
    try:
        client.recv(4096)
    except Exception:
        pass
    client.close()
except Exception:
    pass
PY

exit 0
