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
# Herdr 0.8.0 has no env-var identity pin (upstream feature request:
# herdrdev/herdr#2961), so the argv[0] trick is the working mechanism.
# See CLAUDE.md "Herdr".
#
# Since 2026-08-19 each shim is a repo-tracked auto-reconnect WRAPPER
# (herdr/shims/) symlinked into ~/.local/bin; the raw ssh alias each wrapper
# execs lives in ~/.local/libexec under the same name so the detected process
# name is unchanged. Wrappers retry on any nonzero ssh exit, so the panes
# survive sleep/network loss instead of closing their workspaces.
#
# ln -sf is idempotent; a live pane keeps its already-exec'd process either way.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would symlink ~/.local/bin/{hermes-agent,claude-code} -> herdr/shims/ wrappers"
  echo "[dry-run] would symlink ~/.local/libexec/{hermes-agent,claude-code} -> /usr/bin/ssh"
  exit 0
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/libexec"
chmod +x "$REPO_ROOT/herdr/shims/hermes-agent" "$REPO_ROOT/herdr/shims/claude-code"
ln -sf "$REPO_ROOT/herdr/shims/hermes-agent" "$HOME/.local/bin/hermes-agent"
ln -sf "$REPO_ROOT/herdr/shims/claude-code" "$HOME/.local/bin/claude-code"
ln -sf /usr/bin/ssh "$HOME/.local/libexec/hermes-agent"
ln -sf /usr/bin/ssh "$HOME/.local/libexec/claude-code"
echo "herdr agent shims installed: wrappers in ~/.local/bin, ssh aliases in ~/.local/libexec"
