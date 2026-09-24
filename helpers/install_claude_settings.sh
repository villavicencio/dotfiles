#!/usr/bin/env bash
#
# install_claude_settings.sh — seed Claude Code's user-scope settings.json.
#
# SEED-ONLY BY DESIGN, for the same reason the retired Otty config was (git history):
# ~/.claude/settings.json has TWO independent writers besides this repo —
# Claude Code itself (effortLevel, tui, notification prefs, autoMode) and
# `herdr integration install`. (A third, Otty's agent-integration installer, went
# away with Otty on 2026-09-03.) Each rewrites the file in place, so a Dotbot `link:` there survives only until the
# next write, after which the live file is a regular file and the repo copy is a
# silently-orphaned stale twin.
#
# That is not hypothetical: the link was replaced at some point before
# 2026-08-25, and the repo copy went stale from 2026-08-07 (the last commit that
# touched it) until the drift was found. In the meantime the live file had
# regrown a legacy top-level `allowedTools` key holding 18 rules while
# `permissions.allow` was down to 1 — silently re-arming the precedence trap that
# PR #127 had removed, because the legacy key wins when both exist.
#
# So: copy in only what is absent, never clobber a live config, and let
# `dot drift` surface the gap. Use --capture to fold live changes back.
#
# Usage:
#   install_claude_settings.sh            seed ~/.claude/settings.json if absent
#   install_claude_settings.sh --capture  the reverse — record live changes into the repo
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/claude/settings.json"
DEST="$HOME/.claude/settings.json"
# Windows (Git Bash) tracks a hook-free sibling, which install.ps1 seeds. Point
# at it here too, or --capture run on the PC would overwrite the Mac baseline
# with a file that has no hooks.
IS_WINDOWS=0
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1; SRC="$REPO_ROOT/windows/claude-settings.json" ;;
esac
SRC_REL="${SRC#"$REPO_ROOT"/}"   # for messages: claude/settings.json or windows/claude-settings.json

# A native Windows python can't open a Git Bash path (/c/Users/...); hand it
# the C:\... form. Everywhere else the path passes through unchanged.
native_path() {
  if [ "$IS_WINDOWS" -eq 1 ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

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

# Dry-run guard comes FIRST so it covers --capture too: capture writes to the
# repo, and `DOTFILES_DRY_RUN=1 ... --capture` must not mutate anything.
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  if [ "${1:-}" = "--capture" ]; then
    echo "[dry-run] would capture ~/.claude/settings.json into $SRC_REL"
  else
    echo "[dry-run] would seed ~/.claude/settings.json from $SRC_REL if absent"
  fi
  exit 0
fi

if [ "${1:-}" = "--capture" ]; then
  [ -f "$DEST" ] || { echo "Error: no live settings at $DEST" >&2; exit 1; }
  [ -f "$SRC" ]  || { echo "Error: tracked settings missing at $SRC" >&2; exit 1; }
  # Probe by running it: on Windows `python3` is often the Microsoft Store
  # placeholder, which `command -v` finds but which exits non-zero.
  PYTHON=""
  for _py in python3 python; do
    if "$_py" -c 'import sys' >/dev/null 2>&1; then PYTHON="$_py"; break; fi
  done
  [ -n "$PYTHON" ] || { echo "Error: no working python3/python on PATH" >&2; exit 1; }

  STRIP_KEYS="$STRIP_KEYS" SRC="$(native_path "$SRC")" DEST="$(native_path "$DEST")" \
    SRC_REL="$SRC_REL" PYTHON="$PYTHON" "$PYTHON" - <<'PY' || exit 1
import json, collections, os, sys

src, dest = os.environ["SRC"], os.environ["DEST"]
strip = set(os.environ["STRIP_KEYS"].split())

try:
    live = json.load(open(dest, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
except Exception as e:
    print("Error: live settings is not valid JSON (%s) — nothing captured" % e, file=sys.stderr)
    raise SystemExit(1)
tracked = json.load(open(src, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)

# `allowedTools` is dropped rather than tracked — but dropping it while it still
# holds rules absent from permissions.allow would SILENTLY DELETE them from the
# tracked baseline, and the legacy key is the one Claude Code actually enforces.
# Refuse, and point at the migration that folds them back.
legacy = live.get("allowedTools") or []
allow_now = (live.get("permissions") or {}).get("allow") or []
unmerged = [r for r in legacy if r not in allow_now]
if unmerged:
    print(
        "Error: live settings still has a legacy 'allowedTools' key with %d rule(s)\n"
        "       not present in permissions.allow. Capturing now would silently drop\n"
        "       them. Run this first, then re-capture (on Windows it only folds\n"
        "       allowedTools; it registers no herdr hooks there):\n"
        "           %s helpers/migrate_claude_settings.py\n"
        "       Unmerged: %s" % (len(unmerged), os.environ["PYTHON"], ", ".join(unmerged[:5])),
        file=sys.stderr,
    )
    raise SystemExit(1)

dropped = [k for k in strip if k in live]
for k in dropped:
    live.pop(k)

# Preserve the tracked file's "//" header comment; it explains the whole scheme
# and Claude Code never writes it back.
if "//" in tracked:
    rebuilt = collections.OrderedDict()
    rebuilt["//"] = tracked["//"]
    for k, v in live.items():
        if k != "//":
            rebuilt[k] = v
    live = rebuilt

# Absolute $HOME paths are unportable across machines; installers write them
# (herdr's integration does). Claude Code expands ~ in hook commands, so fold
# them back. Only $HOME is rewritten — /Applications paths are machine-stable.
# Fold the parsed VALUES (and keys), not the serialized blob: on Windows the
# home is C:\Users\<you>, which json.dumps escapes to C:\\Users\\..., so a
# blob-level replace never matches. Windows also gets the forward-slash and
# Git Bash (/c/Users/<you>) spellings.
def home_prefixes():
    home = os.path.expanduser("~").rstrip("\\/")
    cands = {home}
    if os.name == "nt":
        fwd = home.replace("\\", "/")
        cands.add(fwd)
        if len(fwd) > 2 and fwd[1] == ":":
            cands.add("/" + fwd[0].lower() + fwd[2:])
    return sorted(cands, key=len, reverse=True)

def fold_home(v, prefixes):
    if isinstance(v, str):
        for p in prefixes:
            for sep in ("/", "\\"):
                v = v.replace(p + sep, "~/")
        return v
    if isinstance(v, list):
        return [fold_home(x, prefixes) for x in v]
    if isinstance(v, dict):
        return collections.OrderedDict(
            (fold_home(k, prefixes), fold_home(x, prefixes)) for k, x in v.items())
    return v

before = json.dumps(live, indent=2)
live = fold_home(live, home_prefixes())
blob = json.dumps(live, indent=2)
normalized = blob != before

tmp = src + ".tmp.%d" % os.getpid()
try:
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:  # LF even on Windows
        fh.write(blob + "\n")
    json.load(open(tmp, encoding="utf-8"))        # parse-check before replacing
    os.replace(tmp, src)
except Exception:
    if os.path.exists(tmp):
        os.remove(tmp)
    raise

print("Captured live Claude settings into %s" % src)
if dropped:
    print("  dropped machine-local keys: %s" % ", ".join(sorted(dropped)))
if normalized:
    print("  normalized absolute $HOME paths to ~/")
print("  review with: git diff %s" % os.environ["SRC_REL"])
PY
  exit 0
fi

[ -f "$SRC" ] || { echo "Error: tracked settings missing at $SRC" >&2; exit 1; }
mkdir -p "$HOME/.claude" || { echo "Error: cannot create $HOME/.claude" >&2; exit 1; }

if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  echo "Claude settings already present, leaving it alone (run 'dot drift' to compare)."
  exit 0
fi

# Copy to a temp file beside the destination and verify it, THEN publish it with
# `ln`, which creates the name exclusively: it fails if settings.json appeared
# since the check above (Claude Code starting up, say), so a live file is never
# overwritten, and a failed copy never leaves a partial settings.json behind.
# mktemp creates the temp file exclusively (fresh random name, O_EXCL), so a
# pre-planted file or symlink at a guessable name can't redirect the copy.
tmp="$(mktemp "$DEST.seed.XXXXXX")" || { echo "Error: cannot create a temp file beside $DEST" >&2; exit 1; }
if ! cp "$SRC" "$tmp" 2>/dev/null || ! cmp -s "$SRC" "$tmp"; then
  rm -f "$tmp"; echo "Error: could not copy $SRC_REL to $tmp" >&2; exit 1
fi
if ln "$tmp" "$DEST" 2>/dev/null; then
  rm -f "$tmp" || { echo "Error: seeded $DEST but could not remove $tmp" >&2; exit 1; }
  echo "Seeded Claude settings -> $DEST"
elif rm -f "$tmp" || { echo "Error: could not remove $tmp" >&2; exit 1; }; [ -e "$DEST" ] || [ -L "$DEST" ]; then
  echo "Claude settings appeared meanwhile, leaving it alone (run 'dot drift' to compare)."
else
  echo "Error: could not create $DEST" >&2; exit 1
fi
