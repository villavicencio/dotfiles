#!/usr/bin/env bash
#
# The nvim config is a tracked NvChad v2.5 starter, symlinked to ~/.config/nvim
# by Dotbot (whole-directory link — see dotbot-conf/base.yaml). This helper
# bootstraps the pinned plugin set from the committed nvim/lazy-lock.json; it
# does NOT clone NvChad or Packer (the old flow did, which broke fresh machines
# because the tracked overlay targeted removed NvChad v1.0 APIs).
#
# On Linux it first installs Neovim itself: the official release tarball, pinned
# and checksum-verified, into ~/.local (no sudo). Ubuntu's apt `neovim` is 0.9.5,
# far below what this config needs. macOS gets nvim from the Brewfile instead.
# Windows runs windows/install_nvim.ps1, the PowerShell twin of this file.

set -uo pipefail

# Pinned Linux Neovim. Bump all three together; the sha256 values are the `digest`
# fields of the release assets (https://api.github.com/repos/neovim/neovim/releases).
NVIM_VERSION="0.12.5"
NVIM_SHA256_X86_64="bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875"
NVIM_SHA256_ARM64="1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725"

# This config requires Neovim 0.12+: the pinned nvim-treesitter (main branch)
# declares a 0.12 minimum in its health check, init.lua calls vim.uv, and
# lua/configs/lspconfig.lua calls vim.lsp.enable (0.11+).
NVIM_MIN_MINOR=12

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  if [ "$(uname)" = "Linux" ]; then
    echo "[dry-run] would install Neovim v$NVIM_VERSION to ~/.local/opt + link ~/.local/bin/nvim"
  fi
  echo "[dry-run] would bootstrap nvim plugins: nvim --headless \"+Lazy! restore\" +qa"
  exit 0
fi

# --- Linux: Neovim from the official release tarball ------------------------
# Installed to ~/.local/opt/nvim-v<ver>, with ~/.local/bin/nvim a symlink to its
# binary (nvim resolves its runtime from the real executable path, so the link is
# enough). zshenv puts ~/.local/bin ahead of /usr/bin, so this wins over any apt
# copy. Re-running with the same pin is a no-op; a bumped pin installs alongside
# and moves the link (the old version dir stays until removed by hand).
install_linux_nvim() {
  local arch sha
  case "$(uname -m)" in
    x86_64)        arch=x86_64; sha="$NVIM_SHA256_X86_64" ;;
    aarch64|arm64) arch=arm64;  sha="$NVIM_SHA256_ARM64" ;;
    *) echo "install_nvim.sh: no Neovim release tarball for $(uname -m) — install nvim 0.$NVIM_MIN_MINOR+ yourself." >&2
       return 1 ;;
  esac

  local prefix="$HOME/.local/opt/nvim-v$NVIM_VERSION"
  if [ ! -x "$prefix/bin/nvim" ]; then
    echo "Installing Neovim v$NVIM_VERSION ($arch) to $prefix..."
    local url="https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-linux-$arch.tar.gz"
    local tmp; tmp="$(mktemp -d)"
    if ! curl -fsSL --retry 3 -o "$tmp/nvim.tar.gz" "$url"; then
      echo "install_nvim.sh: download failed: $url" >&2; rm -rf "$tmp"; return 1
    fi
    if ! printf '%s  %s\n' "$sha" "$tmp/nvim.tar.gz" | sha256sum -c --status; then
      echo "install_nvim.sh: sha256 mismatch for $url — refusing to install." >&2; rm -rf "$tmp"; return 1
    fi
    mkdir -p "$HOME/.local/opt"
    if ! tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"; then
      echo "install_nvim.sh: could not unpack $url" >&2; rm -rf "$tmp"; return 1
    fi
    rm -rf "$prefix"   # a partial dir from an interrupted earlier run (no executable nvim)
    mv "$tmp/nvim-linux-$arch" "$prefix"
    rm -rf "$tmp"
  fi
  mkdir -p "$HOME/.local/bin"
  # Touch the link only when it points elsewhere, so a re-run changes nothing.
  if [ "$(readlink "$HOME/.local/bin/nvim" 2>/dev/null)" != "$prefix/bin/nvim" ]; then
    ln -sfn "$prefix/bin/nvim" "$HOME/.local/bin/nvim"
  fi
  # Fail loudly rather than let the version gate below read a binary that can't
  # start (e.g. a glibc older than the release was built against) as "too old".
  if ! "$HOME/.local/bin/nvim" --version >/dev/null 2>&1; then
    echo "install_nvim.sh: $prefix/bin/nvim does not run on this system." >&2
    return 1
  fi
}

if [ "$(uname)" = "Linux" ]; then
  install_linux_nvim || exit 1
  # Dotbot's shell steps don't carry zshenv's PATH; resolve the nvim just installed.
  export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "install_nvim.sh: nvim not found on PATH — skipping plugin bootstrap." >&2
  echo "  Install neovim (>=0.$NVIM_MIN_MINOR) and re-run: bash helpers/install_nvim.sh" >&2
  exit 0
fi

# True when the nvim on PATH is new enough; sets $ver for messages.
nvim_new_enough() {
  local vmaj vmin
  ver="$(nvim --version 2>/dev/null | sed -n '1s/.*v\([0-9]*\.[0-9]*\).*/\1/p')"
  [ -n "$ver" ] || return 1
  vmaj="${ver%%.*}"; vmin="${ver#*.}"
  [ "$vmaj" -gt 0 ] || [ "$vmin" -ge "$NVIM_MIN_MINOR" ]
}

# An installed-but-too-old nvim is a failure, not a skip: the Brewfile step only
# installs what is missing, so a Mac that already had 0.11 would otherwise report
# success without the plugin set. On macOS, upgrade through Homebrew and re-check.
if ! nvim_new_enough; then
  if [ "$(uname)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "install_nvim.sh: Neovim ${ver:-unknown} is older than 0.$NVIM_MIN_MINOR — running brew upgrade neovim..."
    brew upgrade neovim || true
    hash -r
  fi
  if ! nvim_new_enough; then
    echo "install_nvim.sh: this config needs Neovim 0.$NVIM_MIN_MINOR+, found ${ver:-unknown} ($(command -v nvim))." >&2
    echo "  (macOS: brew upgrade neovim. Linux: this helper installs v$NVIM_VERSION to ~/.local.)" >&2
    exit 1
  fi
fi

echo "Bootstrapping nvim plugins (Lazy restore from pinned lazy-lock.json)..."
nvim_config_dir="$(nvim --clean --headless --cmd "lua io.write(vim.fn.stdpath('config'))" +qa 2>/dev/null)"
lockfile="${nvim_config_dir:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim}/lazy-lock.json"
if [ ! -f "$lockfile" ]; then
  echo "install_nvim.sh: no lockfile at $lockfile — run ./install first (it links ~/.config/nvim)." >&2
  exit 1
fi

# The first launch is where the pins get lost. lazy.nvim bootstraps itself and
# installs missing plugins in ROUNDS: NvChad's own plugin list (base46, ui,
# gitsigns, nvim-treesitter, ...) is only known once NvChad is on disk, and the
# lockfile rewrite after round one drops every entry it doesn't know yet. Round
# two then installs those plugins at their branch HEAD and writes the drifted
# commits back into nvim/lazy-lock.json through the symlink. A plain
# `Lazy! restore` afterwards restores to that rewritten file, so it looks green.
# Hence: snapshot the pins, bootstrap, put the pins back, restore, verify against
# the snapshot. (Observed 2026-09-24: 9 of 27 plugins drifted on a fresh install.)
pinned=""; diag=""
trap 'rm -f "$pinned" "$diag"' EXIT
if ! pinned="$(mktemp)" || ! diag="$(mktemp)"; then
  echo "install_nvim.sh: could not create temp files — not touching nvim." >&2
  exit 1
fi
# The snapshot is the only copy of the pins once nvim starts, so it must be proven
# complete before nvim runs: copied, non-empty, and byte-equal to the lockfile.
# restore_pins below never writes from anything but this verified copy.
if ! cp "$lockfile" "$pinned" || [ ! -s "$pinned" ] || ! cmp -s "$lockfile" "$pinned"; then
  echo "install_nvim.sh: could not snapshot $lockfile — not starting nvim." >&2
  exit 1
fi
restore_pins() {
  cmp -s "$pinned" "$lockfile" && return 0
  # Write through the link so the tracked file is restored, then prove it was.
  if ! cat "$pinned" > "$lockfile" || ! cmp -s "$pinned" "$lockfile"; then
    echo "install_nvim.sh: could not restore the pinned $lockfile (it is left drifted)." >&2
    return 1
  fi
  echo "  restored the pinned lazy-lock.json (the bootstrap install had rewritten it)"
}

# Pass 1: bootstrap/install (output is almost all git progress). Pass 2: restore
# to the pins; keep its stderr for diagnostics. Neither exit code is trusted —
# `nvim --headless +qa` exits 0 even on a broken config — the verify below is.
nvim --headless +qa >/dev/null 2>&1 || true
restore_pins || exit 1
nvim --headless "+Lazy! restore" +qa >/dev/null 2>"$diag" || true
restore_pins || exit 1

# Verify EVERY locked plugin is at its recorded commit with a clean checkout
# (helpers/nvim_verify_lock.lua runs inside nvim, shared with Windows).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nvim -l "$here/nvim_verify_lock.lua" "$pinned"; rc=$?

if [ "$rc" -eq 0 ]; then
  echo "nvim: all pinned plugins present at their locked commits; bootstrap complete."
  exit 0
fi

echo "install_nvim.sh: nvim plugin bootstrap INCOMPLETE (see above)." >&2
echo "  (If ~/.config/nvim isn't a symlink to this repo yet, run ./install first.)" >&2
if [ -s "$diag" ]; then
  echo "  --- last restore stderr ---" >&2
  sed 's/^/  /' "$diag" >&2
fi
echo "  Open nvim (it finishes installing on launch), then run :Lazy restore + :checkhealth." >&2
exit 1
