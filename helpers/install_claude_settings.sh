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

# Keys that are machine- or session-specific and must never be tracked. The
# file's own "//" header states the rule; these are the observed offenders.
#   effortLevel  session pin
#   autoMode     per-project classifier context (has leaked a project's
#                trusted-repo path and service list into user scope before)
#   mcpServers   per-machine server definitions
#   allowedTools LEGACY key — silently overrides permissions.allow. Never track
#                it; capture drops it so a stale live file cannot reintroduce it.
STRIP_KEYS="effortLevel autoMode mcpServers allowedTools"

# Dry-run guard comes FIRST so it covers --capture too: capture writes to the
# repo, and `DOTFILES_DRY_RUN=1 ... --capture` must not mutate anything.
if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  if [ "${1:-}" = "--capture" ]; then
    echo "[dry-run] would capture ~/.claude/settings.json into claude/settings.json"
  else
    echo "[dry-run] would seed ~/.claude/settings.json from claude/settings.json if absent"
  fi
  exit 0
fi

if [ "${1:-}" = "--capture" ]; then
  [ -f "$DEST" ] || { echo "Error: no live settings at $DEST" >&2; exit 1; }
  [ -f "$SRC" ]  || { echo "Error: tracked settings missing at $SRC" >&2; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not on PATH" >&2; exit 1; }

  STRIP_KEYS="$STRIP_KEYS" SRC="$SRC" DEST="$DEST" python3 - <<'PY' || exit 1
import json, collections, os, sys

src, dest = os.environ["SRC"], os.environ["DEST"]
strip = set(os.environ["STRIP_KEYS"].split())

try:
    live = json.load(open(dest), object_pairs_hook=collections.OrderedDict)
except Exception as e:
    print("Error: live settings is not valid JSON (%s) — nothing captured" % e, file=sys.stderr)
    raise SystemExit(1)
tracked = json.load(open(src), object_pairs_hook=collections.OrderedDict)

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
        "       them. Run this first, then re-capture:\n"
        "           python3 helpers/migrate_claude_settings.py\n"
        "       Unmerged: %s" % (len(unmerged), ", ".join(unmerged[:5])),
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

# Absolute $HOME paths are unportable across the two Macs; installers write them
# (herdr's integration does). Claude Code expands ~ in hook commands, so fold
# them back. Only $HOME is rewritten — /Applications paths are machine-stable.
blob = json.dumps(live, indent=2)
home = os.path.expanduser("~")
before = blob
blob = blob.replace(home + "/", "~/")
normalized = blob != before

tmp = src + ".tmp.%d" % os.getpid()
try:
    with open(tmp, "w") as fh:
        fh.write(blob + "\n")
    json.load(open(tmp))          # parse-check before replacing
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
print("  review with: git diff claude/settings.json")
PY
  exit 0
fi

[ -f "$SRC" ] || { echo "Error: tracked settings missing at $SRC" >&2; exit 1; }
mkdir -p "$HOME/.claude" || { echo "Error: cannot create $HOME/.claude" >&2; exit 1; }

if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  echo "Claude settings already present, leaving it alone (run 'dot drift' to compare)."
  exit 0
fi

cp "$SRC" "$DEST" && echo "Seeded Claude settings -> $DEST"
