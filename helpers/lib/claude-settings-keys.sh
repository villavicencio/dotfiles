# shellcheck shell=bash
# shellcheck disable=SC2034  # both lists are read by the scripts that source this file
#
# Sourced by helpers/install_claude_settings.sh (--capture) and
# helpers/report_drift.sh (`dot drift`), so both leave out the same things.
# helpers/migrate_claude_settings.py keeps its own copy of STRIP_KEYS as
# MACHINE_LOCAL; `dot check` fails if the two differ.

# Keys that are machine- or session-specific and must never be tracked. The
# file's own "//" header states the rule; these are the observed offenders.
#   effortLevel  session pin
#   modelSettings per-model pins (e.g. {"claude-opus-5-5": {"effortLevel": ...}}),
#                the newer home of the effort pin — seen live on the Windows PC
#   autoMode    per-project classifier context (has leaked a project's
#                trusted-repo path and service list into user scope before)
#   mcpServers   per-machine server definitions
#   allowedTools LEGACY key — silently overrides permissions.allow. Never track
#                it; capture drops it so a stale live file cannot reintroduce it.
STRIP_KEYS="effortLevel modelSettings autoMode mcpServers allowedTools"

# Hooks an agent-integration installer writes into the live file and owns (VIL-431). A hook
# whose command contains one of these is left out of capture
# and out of `dot drift`: the installer writes it back, and machines
# without that app don't need it. Space-separated substrings, matched with or without ~/.
#   .orca/agent-hooks/        Orca's agent hooks (one inline command per event)
#   .config/iterm2/cc-status  iTerm2's Claude Code status hook
INSTALLER_HOOKS=".orca/agent-hooks/ .config/iterm2/cc-status"
