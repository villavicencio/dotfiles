#!/usr/bin/env bash
#
# report_drift.sh — READ-ONLY report of drift between this machine and the
# tracked manifests (brew/Brewfile, npm/npm-requirements.txt, otty/).
#
# It NEVER modifies any manifest. It replaces the old regenerate-from-machine
# habit (`brew bundle dump` / `ls $(npm root -g)`), which (a) recorded
# transitive dependencies as fake intent and (b) mangled scoped npm packages
# (`ls $(npm root -g)` lists `@scope` as one entry, losing `@scope/name`).
#
# It reports only INTENT-level drift: intentionally-installed formulae (every
# one whose receipt has installed_on_request), casks, taps, and global npm
# packages — never the pure transitive dependency graph. If it cannot read an
# authoritative inventory it
# says so on stderr and exits non-zero, so a failure can't masquerade as a
# clean report.
#
# Usage: helpers/report_drift.sh   (run from anywhere)
set -uo pipefail

# Keep this strictly read-only: stop `brew` from auto-updating its own repos
# (a network fetch + writes under the Homebrew prefix) as a side effect of the
# `brew bundle check` / `leaves` / `tap` calls below.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$REPO_ROOT/brew/Brewfile"
NPM_REQ="$REPO_ROOT/npm/npm-requirements.txt"
status=0

hr() { printf '\n== %s ==\n' "$1"; }
indent() { sed 's/^/  /'; }
# Print the lines in $1 that are not in $2, indented; "(none)" if empty.
only_in_first() { comm -23 <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep . | indent || echo "  (none)"; }
only_in_second() { comm -13 <(printf '%s\n' "$1") <(printf '%s\n' "$2") | grep . | indent || echo "  (none)"; }

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
  if [ ! -f "$BREWFILE" ]; then
    echo "ERROR: Brewfile not found at $BREWFILE" >&2
    exit 2
  fi

  # Recorded but not satisfied. `brew bundle check` exits 0 (satisfied) or 1
  # (unsatisfied) — both expected; a higher code is a real failure.
  check_out="$(brew bundle check --file="$BREWFILE" --verbose 2>&1)"; check_rc=$?
  if [ "$check_rc" -gt 1 ] || printf '%s\n' "$check_out" | grep -qiE '^Error|SyntaxError'; then
    echo "ERROR: 'brew bundle check' failed (exit $check_rc):" >&2
    printf '%s\n' "$check_out" | indent >&2
    status=1
  fi
  hr "Homebrew: recorded but not satisfied (in Brewfile, not installed / outdated)"
  printf '%s\n' "$check_out" | grep -iE 'needs? to be installed|not installed|would install' | indent \
    || echo "  (none)"

  # Manifest sets.
  bf_formulae="$(grep -E '^brew ' "$BREWFILE" | sed -E 's/^brew "([^"]+)".*/\1/; s|.*/||' | sort -u)"
  bf_casks="$(grep -E '^cask ' "$BREWFILE" | sed -E 's/^cask "([^"]+)".*/\1/' | sort -u)"
  bf_taps="$(grep -E '^tap ' "$BREWFILE" | sed -E 's/^tap "([^"]+)".*/\1/' | sort -u)"

  # Machine inventories. Fail loudly if any can't be read.
  #
  # Use the COMPLETE set of intentionally-installed formulae (every one whose
  # install receipt has installed_on_request), not `brew leaves
  # --installed-on-request` — the latter drops on-request formulae that later
  # became a dependency of something else, silently omitting real intent.
  # Normalize BOTH sides to the basename so a tap-qualified machine entry
  # (`oven-sh/bun/bun`) matches a Brewfile entry however written (`bun` or the
  # qualified form). (Basename collisions across taps are possible but rare.)
  if ! onrequest="$(brew info --json=v2 --installed 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(3)
out = set()
for f in d.get("formulae", []):
    for inst in f.get("installed", []):
        if inst.get("installed_on_request"):
            out.add(f["name"].split("/")[-1])
            break
for n in sorted(out):
    print(n)
' 2>/dev/null)" || [ -z "$onrequest" ]; then
    echo "ERROR: 'brew info --json' returned no on-request formulae — cannot compute formula drift" >&2
    status=1; onrequest=""
  fi
  if ! casks="$(brew list --cask -1 2>/dev/null | sort -u)"; then
    echo "ERROR: 'brew list --cask' failed — cannot compute cask drift" >&2
    status=1; casks=""
  fi
  if ! taps="$(brew tap 2>/dev/null | sort -u)"; then
    echo "ERROR: 'brew tap' failed — cannot compute tap drift" >&2
    status=1; taps=""
  elif [ -n "$taps" ] && printf '%s\n' "$taps" | grep -qvE '^[^[:space:]/]+/[^[:space:]/]+$'; then
    echo "ERROR: 'brew tap' returned lines that are not owner/repo taps — refusing to report tap drift" >&2
    status=1; taps=""
  fi

  hr "Homebrew: top-level formulae installed but NOT in Brewfile (unrecorded intent)"
  only_in_first "$onrequest" "$bf_formulae"
  hr "Homebrew: casks installed but NOT in Brewfile"
  only_in_first "$casks" "$bf_casks"
  hr "Homebrew: active taps not in Brewfile"
  only_in_first "$taps" "$bf_taps"
else
  echo "ERROR: brew not found on PATH — cannot report Homebrew drift" >&2
  status=1
fi

# ---------------------------------------------------------------------------
# npm globals (scoped-package aware via --json)
# ---------------------------------------------------------------------------
if command -v npm >/dev/null 2>&1; then
  # Read the global node_modules directory directly rather than `npm ls`, whose
  # JSON output is filtered by inherited config (e.g. npm_config_link/omit) and
  # can silently return a subset of the installed globals. Reading the directory
  # is config-filter-independent and scope-aware; an absent/empty directory is a
  # valid "zero globals" state (e.g. an unusual prefix), not a failure.
  if ! npm_root="$(npm root -g 2>/dev/null)" || [ -z "$npm_root" ]; then
    echo "ERROR: 'npm root -g' failed — cannot read npm global inventory" >&2
    status=1
  else
    installed=""
    inv_ok=1
    if [ ! -d "$npm_root" ]; then
      : # global root does not exist yet -> installed stays "" (valid zero globals)
    elif [ ! -r "$npm_root" ] || [ ! -x "$npm_root" ]; then
      # Searchable-but-unreadable (or fully unreadable) root: the glob would list
      # nothing and be mistaken for "zero globals". Treat as an error instead.
      echo "ERROR: npm global root $npm_root is not readable — cannot list globals" >&2
      status=1; inv_ok=0
    else
      # If the root exists but can't be entered/read, the subshell exits nonzero;
      # capture that so an unreadable root is an error, NOT a false "zero globals".
      if ! installed="$(
        cd "$npm_root" || exit 1
        shopt -s nullglob
        for d in */; do
          name="${d%/}"
          # Skip dotfiles (.bin, .package-lock.json). The leading "(" on the
          # pattern balances the ")" so the enclosing command substitution
          # parses correctly.
          case "$name" in (.*) continue ;; esac
          if [ "${name#@}" != "$name" ]; then
            # scope directory: emit @scope/pkg for each package inside it
            for s in "$name"/*/; do printf '%s\n' "${s%/}"; done
          else
            printf '%s\n' "$name"
          fi
        done | sort -u
      )"; then
        echo "ERROR: could not read npm global root $npm_root (unreadable directory?)" >&2
        status=1; inv_ok=0
      fi
    fi
    # (root absent -> installed stays "" -> a valid zero-globals state)

    if [ "$inv_ok" -eq 0 ]; then
      :   # already errored; skip the manifest comparison for this run
    elif [ ! -f "$NPM_REQ" ]; then
      # -f (not -r): a readable *directory* would pass -r and silently yield an
      # empty manifest.
      echo "ERROR: npm requirements is not a regular file: $NPM_REQ — cannot compute npm drift" >&2
      status=1
    elif ! npm_req_raw="$(cat "$NPM_REQ" 2>/dev/null)"; then
      # Catch read / I/O failures up front, so the parse below runs in-memory and
      # can't mask a read error as an empty manifest.
      echo "ERROR: failed to read $NPM_REQ — cannot compute npm drift" >&2
      status=1
    # Parse in-memory. `sed '/^$/d'` (not `grep -v '^$'`) drops blank lines while
    # returning 0 on empty input, so the pipeline's exit reflects a REAL failure
    # (sed/tr/sort error under pipefail) rather than a benign empty result.
    elif ! recorded="$(printf '%s\n' "$npm_req_raw" | sed 's/#.*//' | tr -d '[:blank:]' | sed '/^$/d' | sort -u)"; then
      echo "ERROR: failed to parse $NPM_REQ — cannot compute npm drift" >&2
      status=1
    else
      hr "npm: installed globals NOT in npm-requirements.txt"
      only_in_first "$installed" "$recorded"
      hr "npm: recorded in npm-requirements.txt but NOT installed"
      only_in_second "$installed" "$recorded"
    fi
  fi
else
  echo "ERROR: npm not found on PATH — cannot report npm drift" >&2
  status=1
fi

# ---------------------------------------------------------------------------
# Otty terminal config
#
# Otty is seeded by COPY, not symlinked (`otty config set` atomic-renames over
# the path and would orphan a link — see helpers/install_otty.sh). A copy can
# drift silently, so it gets a drift report like any other manifest.
#
# Compare the NORMALIZED forms (`otty config show`), not the raw files: the live
# config accumulates a tail of `# key = value (reset to default)` comments that
# would swamp a plain diff with non-differences. `config show` is verified
# read-only and lossless (every live key appears in its output).
# ---------------------------------------------------------------------------
if [ "$(uname)" != "Darwin" ]; then
  : # Otty is a macOS app; nothing to compare
elif ! command -v otty >/dev/null 2>&1; then
  : # Otty not installed on this machine; nothing to compare
else
  OTTY_TRACKED="$REPO_ROOT/otty/config.toml"
  OTTY_LIVE="$HOME/.config/otty/config.toml"
  OTTY_THEME_REL="themes/com-googlecode-iterm2.ottytheme"

  hr "Otty: tracked config vs live ~/.config/otty/config.toml"
  if [ ! -f "$OTTY_TRACKED" ]; then
    echo "ERROR: tracked Otty config missing at $OTTY_TRACKED" >&2
    status=1
  elif [ ! -f "$OTTY_LIVE" ]; then
    echo "  (not seeded on this machine yet — ./install will copy it in)"
  # Normalize both sides. A `config show` failure must not read as "no drift",
  # so capture each into a variable and error out if either command fails.
  elif ! otty_live_norm="$(otty config show --config-file "$OTTY_LIVE" 2>/dev/null)"; then
    echo "ERROR: 'otty config show' failed on $OTTY_LIVE — cannot compute Otty drift" >&2
    status=1
  elif ! otty_tracked_norm="$(otty config show --config-file "$OTTY_TRACKED" 2>/dev/null)"; then
    echo "ERROR: 'otty config show' failed on $OTTY_TRACKED — cannot compute Otty drift" >&2
    status=1
  elif [ "$otty_live_norm" = "$otty_tracked_norm" ]; then
    echo "  (in sync)"
  else
    echo "  live differs from tracked ('<' = live, '>' = repo):"
    diff <(printf '%s\n' "$otty_live_norm") <(printf '%s\n' "$otty_tracked_norm") | indent
    # Not a plain `cp`: the tracked file is the normalized form plus a comment
    # header, both of which a raw copy would destroy. --capture regenerates it.
    echo "  to record: bash helpers/install_otty.sh --capture"
  fi

  hr "Otty: tracked iTerm2-imported theme vs live"
  if [ ! -f "$REPO_ROOT/otty/$OTTY_THEME_REL" ]; then
    echo "ERROR: tracked Otty theme missing at $REPO_ROOT/otty/$OTTY_THEME_REL" >&2
    status=1
  elif [ ! -f "$HOME/.config/otty/$OTTY_THEME_REL" ]; then
    echo "  (not seeded on this machine yet — ./install will copy it in)"
  elif cmp -s "$REPO_ROOT/otty/$OTTY_THEME_REL" "$HOME/.config/otty/$OTTY_THEME_REL"; then
    echo "  (in sync)"
  else
    echo "  live differs from tracked ('<' = live, '>' = repo):"
    diff "$HOME/.config/otty/$OTTY_THEME_REL" "$REPO_ROOT/otty/$OTTY_THEME_REL" | indent
  fi
fi

# ---------------------------------------------------------------------------
# Claude Code settings.json
# ---------------------------------------------------------------------------
# Seeded by COPY, not symlinked: Claude Code itself, `herdr integration install`,
# and Otty's agent-integration installer all rewrite the file in place, so a
# symlink there is orphaned on the first write (see helpers/install_claude_settings.sh).
#
# Compare the CAPTURE-NORMALIZED forms, not the raw files — the live file carries
# machine-local keys (effortLevel, autoMode, mcpServers) that are deliberately
# untracked, so a plain diff would report permanent, un-actionable drift.
CLAUDE_TRACKED="$REPO_ROOT/claude/settings.json"
CLAUDE_LIVE="$HOME/.claude/settings.json"

hr "Claude Code: tracked settings.json vs live ~/.claude/settings.json"
if [ ! -f "$CLAUDE_TRACKED" ]; then
  echo "ERROR: tracked Claude settings missing at $CLAUDE_TRACKED" >&2
  status=1
elif [ ! -f "$CLAUDE_LIVE" ]; then
  echo "  (not seeded on this machine yet — ./install will copy it in)"
elif ! command -v python3 >/dev/null 2>&1; then
  echo "  (python3 not on PATH — cannot normalize; skipping)"
else
  # Emits the live file reduced to what capture would track, so the diff shows
  # only real, actionable drift.
  claude_norm() {
    CLAUDE_FILE="$1" python3 - <<'PYEOF'
import collections, json, os, sys
strip = {"effortLevel", "autoMode", "mcpServers", "allowedTools"}
try:
    d = json.load(open(os.environ["CLAUDE_FILE"]), object_pairs_hook=collections.OrderedDict)
except Exception as exc:
    print("UNPARSEABLE: %s" % exc); sys.exit(0)
for k in list(d):
    if k in strip or k == "//":
        d.pop(k)
blob = json.dumps(d, indent=2, sort_keys=True)
print(blob.replace(os.path.expanduser("~") + "/", "~/"))
PYEOF
  }
  claude_live_norm="$(claude_norm "$CLAUDE_LIVE")"
  claude_tracked_norm="$(claude_norm "$CLAUDE_TRACKED")"
  if printf '%s' "$claude_live_norm" | grep -q '^UNPARSEABLE'; then
    echo "ERROR: live settings is not valid JSON — cannot compute drift" >&2
    status=1
  elif [ "$claude_live_norm" = "$claude_tracked_norm" ]; then
    echo "  (in sync)"
  else
    echo "  live differs from tracked ('<' = live, '>' = repo):"
    diff <(printf '%s\n' "$claude_live_norm") <(printf '%s\n' "$claude_tracked_norm") | indent
    echo "  to record: bash helpers/install_claude_settings.sh --capture"
  fi
  # The legacy key silently overrides permissions.allow — always worth shouting about.
  if grep -q '"allowedTools"' "$CLAUDE_LIVE"; then
    echo "  WARNING: live settings has a legacy top-level 'allowedTools' key."
    echo "           It OVERRIDES permissions.allow, which is then silently inert."
    echo "           Repair with: python3 helpers/migrate_claude_settings.py"
    status=1
  fi
fi

hr "Done (read-only — no manifests were modified)"
exit "$status"
