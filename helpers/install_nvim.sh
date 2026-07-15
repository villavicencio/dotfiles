#!/usr/bin/env bash
#
# The nvim config is a tracked NvChad v2.5 starter, symlinked to ~/.config/nvim
# by Dotbot (whole-directory link — see dotbot-conf/base.yaml). This helper only
# bootstraps the pinned plugin set from the committed nvim/lazy-lock.json; it
# does NOT clone NvChad or Packer (the old flow did, which broke fresh machines
# because the tracked overlay targeted removed NvChad v1.0 APIs).
#
# init.lua bootstraps lazy.nvim itself on first launch, so all this needs is to
# drive a headless restore to the locked commits — then verify each plugin is
# actually at its locked commit and FAIL CLOSED if not.

set -uo pipefail

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would bootstrap nvim plugins: nvim --headless \"+Lazy! restore\" +qa"
  exit 0
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "install_nvim.sh: nvim not found on PATH — skipping plugin bootstrap." >&2
  echo "  Install neovim (>=0.11) and re-run: bash helpers/install_nvim.sh" >&2
  exit 0
fi

# This config requires Neovim 0.11+ : init.lua calls vim.uv, lua/configs/lspconfig.lua
# calls vim.lsp.enable, and the pinned NvChad declares a 0.11 minimum. Ubuntu's apt
# `neovim` is 0.9.5 — too old. Skip (don't run a doomed restore that would look green).
ver="$(nvim --version 2>/dev/null | sed -n '1s/.*v\([0-9]*\.[0-9]*\).*/\1/p')"
vmaj="${ver%%.*}"; vmin="${ver#*.}"
if [ "${vmaj:-0}" -eq 0 ] && [ "${vmin:-0}" -lt 11 ]; then
  echo "install_nvim.sh: this config needs Neovim 0.11+, found ${ver:-unknown} — skipping bootstrap." >&2
  echo "  (Ubuntu's apt neovim is 0.9.5; use the unstable PPA, snap, or an AppImage for 0.11+.)" >&2
  exit 0
fi

echo "Bootstrapping nvim plugins (Lazy restore from pinned lazy-lock.json)..."
# Restore installs every plugin at its locked commit. The first pass has no base46
# theme cache yet (transient error before base46's build regenerates it); the
# second pass runs with the cache present. Keep the second pass's stderr for
# diagnostics; don't let either non-zero exit abort the installer here.
diag="$(mktemp)"
nvim --headless "+Lazy! restore" +qa >/dev/null 2>/dev/null || true
nvim --headless "+Lazy! restore" +qa >/dev/null 2>"$diag" || true

# Verify EVERY locked plugin is checked out at its recorded commit. A bare
# directory count can be fooled by leftovers or a plugin stuck at a stale commit;
# `nvim --headless +qa` exits 0 even on a broken config. This checks git HEAD per
# plugin and fails closed on any missing/mismatched pin.
nvim_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
lazy_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
verify_py="$(mktemp)"
cat > "$verify_py" <<'PY'
import json, os, subprocess, sys
try:
    lock = json.load(open(sys.argv[1]))
except Exception as e:
    print("  lockfile unreadable: %r" % (e,)); sys.exit(2)
lazy = sys.argv[2]

def git(d, *args):
    return subprocess.check_output(["git", "-C", d, *args],
                                   text=True, stderr=subprocess.DEVNULL)

miss, bad, ok = [], [], 0
for name, meta in lock.items():
    want = (meta or {}).get("commit")
    d = os.path.join(lazy, name)
    if not os.path.isdir(os.path.join(d, ".git")):
        miss.append(name); continue
    try:
        head = git(d, "rev-parse", "HEAD").strip()
        # A plugin can sit at the right HEAD yet have modified/deleted tracked
        # files (a corrupt checkout) or dirty submodules; require both clean.
        dirty = git(d, "status", "--porcelain", "--untracked-files=no").strip()
        subm = git(d, "submodule", "status", "--recursive")
    except Exception:
        miss.append(name); continue
    subm_bad = any(ln[:1] in ("-", "+", "U") for ln in subm.splitlines() if ln)
    if (want and head != want) or dirty or subm_bad:
        bad.append(name)
    else:
        ok += 1
print("  %d/%d plugins at their locked commit (clean checkout)" % (ok, len(lock)))
if miss:
    print("  missing:  " + " ".join(sorted(miss)))
if bad:
    print("  mismatch/dirty: " + " ".join(sorted(bad)))
sys.exit(0 if (not miss and not bad) else 1)
PY
python3 "$verify_py" "$nvim_config_dir/lazy-lock.json" "$lazy_dir"; rc=$?
rm -f "$verify_py"

if [ "$rc" -eq 0 ]; then
  echo "nvim: all pinned plugins present at their locked commits; bootstrap complete."
  rm -f "$diag"; exit 0
fi

echo "install_nvim.sh: nvim plugin bootstrap INCOMPLETE (see above)." >&2
echo "  (If ~/.config/nvim isn't a symlink to this repo yet, run ./install first.)" >&2
if [ -s "$diag" ]; then
  echo "  --- last restore stderr ---" >&2
  sed 's/^/  /' "$diag" >&2
fi
echo "  Open nvim (it finishes installing on launch), then run :Lazy restore + :checkhealth." >&2
rm -f "$diag"
exit 1
