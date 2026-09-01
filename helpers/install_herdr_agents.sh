#!/usr/bin/env bash
#
# install_herdr_agents.sh — seed the ssh argv[0] shims herdr's agent
# detection depends on.
#
# Herdr identifies a pane's agent by PROCESS NAME against its detection
# manifests. `claude-code` (claude manifest) is an alias name no real binary
# uses on this machine, so pointing it at ssh makes a remote attach register
# as that agent. Two panes share the alias and are told apart by
# `herdr agent rename`:
#   claude-code -> the VPS AXIOM Claude Code (workspace "axiom")
#              and the VPS atlas-tools Claude Code (workspace "atlas-tools")
#
# The `hermes-agent` shim was retired 2026-09-01 with the `atlas` workspace,
# when Atlas moved to the official Hermes Desktop app. It was the only consumer.
# Historical note: a Hermes install used to clobber that shim (it ships its own
# `hermes-agent` entrypoint) — with the shim gone that collision is harmless.
# Write-up kept at ~/Projects/agents/docs/solutions/integration-issues/.
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
# Retired shims are cleaned up below, but only when they are still symlinks INTO
# this repo — never a real binary a later install legitimately put there.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would symlink ~/.local/bin/claude-code -> herdr/shims/claude-code"
  echo "[dry-run] would symlink ~/.local/libexec/claude-code -> /usr/bin/ssh"
  for stale in "$HOME/.local/bin/hermes-agent" "$HOME/.local/libexec/hermes-agent"; do
    [ -L "$stale" ] && echo "[dry-run] would consider removing retired shim link $stale"
  done
  exit 0
fi

# Migration (retired 2026-09-01 with the `atlas` workspace). Remove the old
# hermes-agent links ONLY when they are the links this helper created: a symlink
# in ~/.local/bin pointing into this repo's shims, and a symlink in
# ~/.local/libexec pointing at ssh. A regular file is left alone — upstream
# Hermes ships its own `hermes-agent` entrypoint, and that one is legitimate.
old_bin="$HOME/.local/bin/hermes-agent"
if [ -L "$old_bin" ] && [[ "$(readlink "$old_bin")" == */herdr/shims/hermes-agent ]]; then
  rm -f "$old_bin"
  echo "removed retired shim link: $old_bin"
fi
old_libexec="$HOME/.local/libexec/hermes-agent"
if [ -L "$old_libexec" ] && [[ "$(readlink "$old_libexec")" == */ssh ]]; then
  rm -f "$old_libexec"
  echo "removed retired shim link: $old_libexec"
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/libexec"
chmod +x "$REPO_ROOT/herdr/shims/claude-code"
ln -sf "$REPO_ROOT/herdr/shims/claude-code" "$HOME/.local/bin/claude-code"
ln -sf /usr/bin/ssh "$HOME/.local/libexec/claude-code"
echo "herdr agent shim installed: wrapper in ~/.local/bin, ssh alias in ~/.local/libexec"
