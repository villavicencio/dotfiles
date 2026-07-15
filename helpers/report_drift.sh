#!/usr/bin/env bash
#
# report_drift.sh — READ-ONLY report of drift between this machine and the
# tracked manifests (brew/Brewfile, npm/npm-requirements.txt).
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

hr "Done (read-only — no manifests were modified)"
exit "$status"
