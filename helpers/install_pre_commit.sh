#!/usr/bin/env bash
# Install pre-commit framework + gitleaks binary, then wire .git/hooks/pre-commit
# for this dotfiles repo (where commits to public history motivated the gate —
# see docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md).
#
# Darwin: pre-commit + gitleaks come from Brewfile via install_packages.sh
#         (which runs ahead of this helper in install.conf.yaml). This script
#         then runs `pre-commit install` to wire the hook.
# Linux:  pre-commit via pipx (pipx itself comes from install_packages.sh apt
#         block); gitleaks via GitHub release binary download into ~/.local/bin
#         (no apt package as of Ubuntu 24.04). The VPS rarely commits, but
#         keeping the helper cross-platform avoids "works on Mac, fails on
#         Linux" surprises if a commit ever happens there.
#
# Idempotent: rerunning skips already-installed components.

set -eo pipefail

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would install pre-commit + gitleaks and wire .git/hooks/pre-commit"
  exit 0
fi

# Pinned to match .pre-commit-config.yaml's `rev:` so the system binary version
# matches the hook config. Bump both together.
GITLEAKS_VERSION="8.30.1"

if [ "$(uname)" = "Linux" ]; then
  if ! command -v pre-commit >/dev/null 2>&1; then
    echo "Installing pre-commit via pipx..."
    pipx install pre-commit
  else
    echo "pre-commit already installed: $(pre-commit --version)"
  fi

  if ! command -v gitleaks >/dev/null 2>&1; then
    echo "Installing gitleaks v${GITLEAKS_VERSION} from GitHub release..."
    LOCAL_BIN="$HOME/.local/bin"
    mkdir -p "$LOCAL_BIN"

    case "$(uname -m)" in
      x86_64)        GL_ARCH="x64" ;;
      aarch64|arm64) GL_ARCH="arm64" ;;
      *) echo "ERROR: unsupported arch $(uname -m) for gitleaks binary" >&2; exit 1 ;;
    esac

    TARBALL="gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz"
    URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${TARBALL}"
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    curl -fsSL "$URL" -o "$TMPDIR/$TARBALL"
    tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
    install -m 0755 "$TMPDIR/gitleaks" "$LOCAL_BIN/gitleaks"
    echo "Installed gitleaks to $LOCAL_BIN/gitleaks"
  else
    echo "gitleaks already installed: $(gitleaks version)"
  fi
fi

# Both platforms: wire .git/hooks/pre-commit. Safe to rerun — pre-commit
# overwrites the hook file each invocation.
if [ ! -f .pre-commit-config.yaml ]; then
  echo "ERROR: .pre-commit-config.yaml not found in $(pwd)" >&2
  exit 1
fi

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "ERROR: pre-commit not on PATH after install attempt" >&2
  exit 1
fi

pre-commit install
