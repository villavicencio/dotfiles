#!/usr/bin/env bash

# Install Claude Code via Anthropic's native installer.
#
# Authoritative entry point is ~/.local/bin/claude → ~/.local/share/claude/versions/<latest>.
# The Homebrew cask perpetually lags (weeks behind at times) so dotfiles prefers
# the native installer and relies on Claude Code's own auto-updater afterwards.
# PATH ordering in zsh/zshenv puts ~/.local/bin ahead of Homebrew — PR #36/#37.

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install Claude Code via curl -fsSL https://claude.ai/install.sh | bash"
  exit 0
fi

if [ "$(uname)" != "Darwin" ]; then
  echo "install_claude_code.sh: non-Darwin host, skipping"
  exit 0
fi

if [ -x "$HOME/.local/bin/claude" ]; then
  echo "Claude Code already installed at ~/.local/bin/claude — skipping (auto-updater handles updates)"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "install_claude_code.sh: curl not found, cannot install Claude Code" >&2
  exit 1
fi

echo "Installing Claude Code via native installer..."
curl -fsSL https://claude.ai/install.sh | bash
