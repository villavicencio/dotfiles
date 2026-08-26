#!/usr/bin/env bash
#
# install_uv.sh — install uv via Astral's native installer.
#
# Authoritative entry point is ~/.local/bin/uv. Deliberately NOT in the Brewfile:
# zsh/zshenv puts ~/.local/bin ahead of Homebrew on PATH, so a `brew install uv`
# would sit at a lower-precedence path and never be the copy that runs — two uvs,
# with the tracked one permanently shadowed. uv also self-updates
# (`uv self update`), so a Homebrew copy would drift behind the live one anyway.
# Same reasoning, and the same shape, as helpers/install_claude_code.sh.
#
# UV_NO_MODIFY_PATH=1 is REQUIRED, not cosmetic. Left unset, the installer appends
# PATH lines to `.zshrc` and `.zshenv` (see add_install_dir_to_path in the
# installer). Those paths are Dotbot symlinks into this repo, so an unguarded run
# edits tracked files and dirties the working tree — exactly the hazard the
# "Post-installer audit" section of CLAUDE.md exists for. zshenv already puts
# ~/.local/bin on PATH, so there is nothing for the installer to add.
#
# Who needs uv: the Hermes runtime, and any project pinning its own Python
# (`uv python install`). uv prefers the interpreters it manages under
# ~/.local/share/uv/python and provisions one on demand, so no Homebrew python@3.x
# has to be installed for it. uv will still discover and use a suitable system
# interpreter when no managed one fits, so a brewed Python is redundant here rather
# than unusable.
set -uo pipefail

INSTALL_DIR="$HOME/.local/bin"
UV_BIN="$INSTALL_DIR/uv"
UVX_BIN="$INSTALL_DIR/uvx"
INSTALLER_URL="https://astral.sh/uv/install.sh"

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install uv via curl -LsSf $INSTALLER_URL | sh (UV_NO_MODIFY_PATH=1)"
  exit 0
fi

if [ "$(uname)" != "Darwin" ]; then
  echo "install_uv.sh: non-Darwin host, skipping"
  exit 0
fi

# Both binaries must be present AND runnable. The installer places uv and uvx
# together, so a working uv beside a missing or broken uvx is still a half install —
# and skipping on mere existence would strand it forever.
runnable() { [ -x "$1" ] && out="$("$1" --version 2>/dev/null)" && [ -n "$out" ]; }

if [ -e "$UV_BIN" ] || [ -e "$UVX_BIN" ]; then
  if runnable "$UV_BIN" && runnable "$UVX_BIN"; then
    echo "uv already installed at $UV_BIN ($("$UV_BIN" --version)) — skipping (self-updates via 'uv self update')"
    exit 0
  fi
  echo "Found an incomplete uv install at $INSTALL_DIR (uv or uvx missing / not runnable) — reinstalling over it." >&2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl not found; cannot install uv" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR" || { echo "Error: cannot create $INSTALL_DIR" >&2; exit 1; }

echo "Installing uv via Astral's native installer..."
if ! curl -LsSf "$INSTALLER_URL" \
     | env UV_NO_MODIFY_PATH=1 UV_INSTALL_DIR="$INSTALL_DIR" sh; then
  echo "Error: uv installation failed" >&2
  exit 1
fi

for bin in "$UV_BIN" "$UVX_BIN"; do
  if ! runnable "$bin"; then
    echo "Error: installer reported success but $bin is missing or does not run ('--version' failed)" >&2
    exit 1
  fi
done

echo "Installed uv -> $UV_BIN ($("$UV_BIN" --version)), uvx -> $UVX_BIN"
