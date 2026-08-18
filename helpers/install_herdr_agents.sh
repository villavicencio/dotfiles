#!/usr/bin/env bash
#
# install_herdr_agents.sh — seed the ssh argv[0] shims herdr's agent
# detection depends on.
#
# Herdr identifies a pane's agent by PROCESS NAME against its detection
# manifests. `hermes-agent` (hermes manifest) and `claude-code` (claude
# manifest) are alias names no real binary uses on this machine, so pointing
# them at ssh makes a remote attach register as that agent:
#   hermes-agent -> the VPS Hermes TUI (workspace "atlas")
#   claude-code  -> the VPS AXIOM Claude Code (workspace "axiom")
# The HERDR_AGENT env pin does not work for spawned panes on herdr 0.8.0, so
# the argv[0] trick is the working mechanism. See CLAUDE.md "Herdr".
#
# ln -sf is idempotent; a live pane keeps its already-exec'd process either way.
set -euo pipefail

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would symlink ~/.local/bin/{hermes-agent,claude-code} -> /usr/bin/ssh"
  exit 0
fi

mkdir -p "$HOME/.local/bin"
ln -sf /usr/bin/ssh "$HOME/.local/bin/hermes-agent"
ln -sf /usr/bin/ssh "$HOME/.local/bin/claude-code"
echo "herdr agent shims linked: hermes-agent, claude-code -> /usr/bin/ssh"
