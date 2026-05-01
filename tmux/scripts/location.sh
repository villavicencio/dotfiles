#!/usr/bin/env bash
# Resolve the current city/region for the tmux status-right pill.
#
# Hot path (no args): emits the cached value (with trailing " · ") and, if
# the cache is missing or stale, kicks an async refresh worker. Returns
# instantly; the status bar never blocks on this script.
#
# Worker (--refresh): runs the platform-specific resolver, sanitizes the
# result, length-caps + display-truncates, and writes the cache atomically.
#
# Sources:
#   Darwin  → CoreLocationCLI (Homebrew cask `corelocationcli`; binary is
#             capitalized; needs Gatekeeper approval + Location Services).
#   Linux   → curl https://ipinfo.io/json + jq + small ISO-3166 inline map.
#
# Cache lives at ${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/, never the
# dotfiles repo. All errors silently fall through to the last-known value.
#
# Recover from a stuck refresh:
#   pkill -f tmux-location-refresh-marker
#
# See: docs/plans/2026-05-01-001-feat-tmux-location-pill-plan.md
#      docs/solutions/best-practices/macos-location-services-tcc-prompt.md

set -u

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location"
cache_file="$cache_dir/value"
lock_dir="$cache_dir/.refresh.lock"

case "$(uname)" in
  Darwin) ttl=1800  ;; # 30 min — travel-friendly on the Mac
  *)      ttl=86400 ;; # 24 h  — VPS doesn't move
esac

self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ── Sanitization + truncation helpers ─────────────────────────────────

# Strip tmux-format-significant chars (#[]{}()), shell metachars (` $ \ ' "),
# and control bytes (0x00-0x1F + 0x7F). Multibyte UTF-8 (·, …, accented
# letters) passes through untouched — those are not dangerous to tmux's
# format engine and are needed by the pill's separator.
# Forged or malformed API responses cannot smuggle a tmux format directive
# through the cache.
sanitize() {
  LC_ALL=C tr -d '#[]{}()`$\\'"'"'"' \
    | LC_ALL=C tr -d '\000-\037\177'
}

# Reject results longer than 64 chars (degenerate/forged payloads).
# Reads one line from stdin; emits empty if cap is exceeded.
cap_length() {
  local s
  IFS= read -r s || return 0
  [ ${#s} -le 64 ] && printf '%s' "$s"
}

# Truncate to ≤ 24 visible chars; append "…" if shortened.
display_truncate() {
  local s
  IFS= read -r s || return 0
  if [ ${#s} -le 24 ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:23}"
  fi
}

# ── Country-code → name map (Linux / IP-geo path) ─────────────────────
# Mac uses CoreLocation's full %country token, so this only fires on Linux.
# Expand on demand if a 2-letter code shows up in the pill.
country_name() {
  case "$1" in
    US) echo "United States"  ;;
    CA) echo "Canada"         ;;
    MX) echo "Mexico"         ;;
    GB) echo "United Kingdom" ;;
    IE) echo "Ireland"        ;;
    FI) echo "Finland"        ;;
    DE) echo "Germany"        ;;
    FR) echo "France"         ;;
    ES) echo "Spain"          ;;
    IT) echo "Italy"          ;;
    PT) echo "Portugal"       ;;
    NL) echo "Netherlands"    ;;
    BE) echo "Belgium"        ;;
    SE) echo "Sweden"         ;;
    NO) echo "Norway"         ;;
    DK) echo "Denmark"        ;;
    IS) echo "Iceland"        ;;
    CH) echo "Switzerland"    ;;
    AT) echo "Austria"        ;;
    JP) echo "Japan"          ;;
    AU) echo "Australia"      ;;
    NZ) echo "New Zealand"    ;;
    *)  echo "$1"             ;;  # un-mapped: fall back to 2-letter code
  esac
}

# ── Platform resolvers ────────────────────────────────────────────────

resolve_darwin() {
  command -v CoreLocationCLI >/dev/null 2>&1 || return 1

  local raw locality region iso country
  raw=$(CoreLocationCLI -format '%locality|%administrativeArea|%isoCountryCode|%country' 2>/dev/null) || return 1
  [ -z "$raw" ] && return 1

  IFS='|' read -r locality region iso country <<< "$raw"
  [ -z "$locality" ] && return 1

  if [ "$iso" = "US" ]; then
    printf '%s, %s' "$locality" "$region"
  elif [ -n "$country" ]; then
    printf '%s, %s' "$locality" "$country"
  else
    printf '%s' "$locality"
  fi
}

resolve_ipgeo() {
  command -v curl >/dev/null 2>&1 || return 1
  command -v jq   >/dev/null 2>&1 || return 1

  local raw city region country_code country_full
  raw=$(curl -sS --max-time 4 'https://ipinfo.io/json' 2>/dev/null) || return 1
  [ -z "$raw" ] && return 1

  city=$(printf '%s' "$raw"         | jq -r '.city    // ""' 2>/dev/null) || return 1
  region=$(printf '%s' "$raw"       | jq -r '.region  // ""' 2>/dev/null) || return 1
  country_code=$(printf '%s' "$raw" | jq -r '.country // ""' 2>/dev/null) || return 1
  [ -z "$city" ] && return 1

  if [ "$country_code" = "US" ]; then
    printf '%s, %s' "$city" "$region"
  elif [ -n "$country_code" ]; then
    country_full=$(country_name "$country_code")
    printf '%s, %s' "$city" "$country_full"
  else
    printf '%s' "$city"
  fi
}

# ── Worker (--refresh) ────────────────────────────────────────────────
if [ "${1:-}" = "--refresh" ]; then
  # Always release the lock on exit, no matter how we got here.
  trap 'rmdir "$lock_dir" 2>/dev/null' EXIT
  mkdir -p "$cache_dir"

  case "$(uname)" in
    Darwin) raw=$(resolve_darwin) || exit 0 ;;
    *)      raw=$(resolve_ipgeo)  || exit 0 ;;
  esac
  [ -z "$raw" ] && exit 0

  cleaned=$(printf '%s' "$raw" | sanitize | cap_length) || exit 0
  [ -z "$cleaned" ] && exit 0

  capped=$(printf '%s' "$cleaned" | display_truncate) || exit 0
  [ -z "$capped" ] && exit 0

  tmp=$(mktemp "${cache_file}.XXXXXX") || exit 0
  printf '%s · ' "$capped" > "$tmp"
  mv "$tmp" "$cache_file"
  exit 0
fi

# ── Hot path (no args): cache read + maybe-spawn-worker ───────────────
mkdir -p "$cache_dir"

# Belt-and-suspenders: sanitize on read too. The worker sanitizes on write,
# but if the cache file ever gets tampered with (or was written by an older
# buggy script version), this stops bad bytes reaching the tmux format engine.
if [ -f "$cache_file" ]; then
  cat "$cache_file" | sanitize
fi

# Decide whether to refresh.
needs_refresh=0
if [ ! -f "$cache_file" ]; then
  needs_refresh=1
else
  if   stat -f %m "$cache_file" >/dev/null 2>&1; then mtime=$(stat -f %m "$cache_file")  # BSD (macOS)
  elif stat -c %Y "$cache_file" >/dev/null 2>&1; then mtime=$(stat -c %Y "$cache_file")  # GNU (Linux)
  else mtime=0
  fi
  now=$(date +%s)
  [ $((now - mtime)) -ge "$ttl" ] && needs_refresh=1
fi

if [ "$needs_refresh" = "1" ]; then
  # Stale-lock self-heal: remove a lock dir older than 60 s before claiming.
  # Survives a worker crash between mkdir and rmdir.
  if [ -d "$lock_dir" ] && find "$lock_dir" -maxdepth 0 -type d -mmin +1 -print -quit 2>/dev/null | grep -q .; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi

  # Atomic claim. If another worker already holds the lock, skip silently.
  if mkdir "$lock_dir" 2>/dev/null; then
    marker="tmux-location-refresh-marker-$(hostname -s 2>/dev/null || echo unknown)"
    # exec -a renames argv[0] so `pkill -f tmux-location-refresh-marker` finds the worker.
    ( exec -a "$marker" bash "$self" --refresh ) >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi

exit 0
