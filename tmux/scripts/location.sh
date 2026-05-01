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

# Platform detected once — referenced on every hot-path tick AND in the worker.
platform="$(uname)"

case "$platform" in
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
# Reads one line from stdin — the resolver pipes its output without a
# trailing newline, so `read -r` returns non-zero on EOF; that does NOT
# mean the read failed. $s still holds the partial line content; use it.
cap_length() {
  local s
  IFS= read -r s
  [ ${#s} -le 64 ] && printf '%s' "$s"
}

# Truncate to ≤ 24 visible chars; append "…" if shortened.
# Same EOF-without-newline contract as cap_length — operate on $s regardless.
display_truncate() {
  local s
  IFS= read -r s
  if [ ${#s} -le 24 ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:23}"
  fi
}

# ── Country-code → name map (Linux / IP-geo path) ─────────────────────
# Mac uses CoreLocation's full %country token, so this only fires on Linux.
# Expand on demand if a 2-letter code shows up in the pill.
# Uses printf consistently with the rest of the script — no implicit newline.
country_name() {
  case "$1" in
    US) printf "%s" "United States"  ;;
    CA) printf "%s" "Canada"         ;;
    MX) printf "%s" "Mexico"         ;;
    GB) printf "%s" "United Kingdom" ;;
    IE) printf "%s" "Ireland"        ;;
    FI) printf "%s" "Finland"        ;;
    DE) printf "%s" "Germany"        ;;
    FR) printf "%s" "France"         ;;
    ES) printf "%s" "Spain"          ;;
    IT) printf "%s" "Italy"          ;;
    PT) printf "%s" "Portugal"       ;;
    NL) printf "%s" "Netherlands"    ;;
    BE) printf "%s" "Belgium"        ;;
    SE) printf "%s" "Sweden"         ;;
    NO) printf "%s" "Norway"         ;;
    DK) printf "%s" "Denmark"        ;;
    IS) printf "%s" "Iceland"        ;;
    CH) printf "%s" "Switzerland"    ;;
    AT) printf "%s" "Austria"        ;;
    JP) printf "%s" "Japan"          ;;
    AU) printf "%s" "Australia"      ;;
    NZ) printf "%s" "New Zealand"    ;;
    *)  printf "%s" "$1"             ;;  # un-mapped: fall back to 2-letter code
  esac
}

# ── Platform resolvers ────────────────────────────────────────────────

resolve_darwin() {
  command -v CoreLocationCLI >/dev/null 2>&1 || return 1

  # CoreLocationCLI uses Swift ArgumentParser — `--format` (double dash)
  # is the canonical long flag. `-format` (single dash) is silently ignored
  # and the binary defaults to "%latitude %longitude" output.
  #
  # Wrap with `timeout 10` (GNU coreutils, present on Mac via Homebrew and
  # Linux via apt — see helpers/install_packages.sh + brew/Brewfile) to
  # bound CoreLocation hangs. CoreLocationCLI normally exits in ~1s once it
  # has a fix, but if Location Services is denied silently or hardware GPS
  # is unavailable, it can block indefinitely. The 60s lock-TTL self-heal
  # would then re-spawn workers every minute, accumulating stuck binaries.
  local raw
  raw=$(timeout 10 CoreLocationCLI --format '%locality|%administrativeArea|%isoCountryCode|%country' 2>/dev/null) || return 1
  [ -z "$raw" ] && return 1

  local locality region iso country
  IFS='|' read -r locality region iso country <<< "$raw"
  [ -z "$locality" ] && return 1

  if [ "$iso" = "US" ] && [ -n "$region" ]; then
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

  # Single jq call extracts all three fields pipe-delimited; reduces three
  # forks per refresh to one.
  local fields city region country_code country_full
  fields=$(curl -sS --max-time 4 'https://ipinfo.io/json' 2>/dev/null \
    | jq -r '(.city // "") + "|" + (.region // "") + "|" + (.country // "")' 2>/dev/null) \
    || return 1
  [ -z "$fields" ] && return 1

  IFS='|' read -r city region country_code <<< "$fields"
  [ -z "$city" ] && return 1

  if [ "$country_code" = "US" ] && [ -n "$region" ]; then
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
  # Sole lock-release point — do not add rmdir elsewhere; the hot path
  # must not remove a lock it does not own. SIGKILL bypasses the trap;
  # the 60 s lock-TTL self-heal is the documented recovery for that case.
  trap 'rmdir "$lock_dir" 2>/dev/null' EXIT
  mkdir -p "$cache_dir"

  case "$platform" in
    Darwin) raw=$(resolve_darwin) || exit 0 ;;
    *)      raw=$(resolve_ipgeo)  || exit 0 ;;
  esac
  [ -z "$raw" ] && exit 0

  cleaned=$(printf '%s' "$raw" | sanitize | cap_length)
  [ -z "$cleaned" ] && exit 0

  capped=$(printf '%s' "$cleaned" | display_truncate)
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
# buggy script version), this stops bad bytes reaching the tmux format
# engine. Use stdin redirect rather than `cat | sanitize` — saves one fork
# per status-bar tick (status-interval is 1).
if [ -s "$cache_file" ]; then
  sanitize < "$cache_file"
fi

# Decide whether to refresh.
needs_refresh=0
if [ ! -s "$cache_file" ]; then
  # `! -s` (non-existent OR zero-byte) handles a partial-write empty cache
  # the same as a missing one — both should trigger a fresh refresh.
  needs_refresh=1
else
  # Try both stat forms — uname-based dispatch is unsafe because Homebrew's
  # GNU coreutils (installed on this user's Mac and on the VPS) puts a GNU
  # `stat` ahead of BSD `/usr/bin/stat` in PATH. With GNU stat, `-f` means
  # "filesystem status" (multi-line output) and `-c` is the format flag;
  # the BSD-stat-on-Darwin branch then writes filesystem prose into $mtime
  # and the arithmetic below errors. The probe-then-format pattern below
  # works regardless of which `stat` is on PATH.
  if   mtime=$(stat -c %Y "$cache_file" 2>/dev/null) && [ -n "$mtime" ]; then :  # GNU stat
  elif mtime=$(stat -f %m "$cache_file" 2>/dev/null) && [ -n "$mtime" ]; then :  # BSD stat
  else mtime=0
  fi
  now=$(date +%s)
  [ $((now - mtime)) -ge "$ttl" ] && needs_refresh=1
fi

if [ "$needs_refresh" = "1" ]; then
  # Defang lock-as-regular-file DoS: if `.refresh.lock` exists but isn't a
  # directory (e.g., an attacker pre-created it as a file, or a buggy
  # earlier version left one behind), remove it before mkdir. Without this
  # guard, mkdir fails silently forever and the location stays stale.
  if [ -e "$lock_dir" ] && [ ! -d "$lock_dir" ]; then
    rm -f "$lock_dir" 2>/dev/null || true
  fi

  # Stale-lock self-heal: remove a lock dir older than 60 s before claiming.
  # Survives a worker crash between mkdir and rmdir.
  if [ -d "$lock_dir" ] && find "$lock_dir" -maxdepth 0 -type d -mmin +1 -print -quit 2>/dev/null | grep -q .; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi

  # Atomic claim. If another worker already holds the lock, skip silently.
  if mkdir "$lock_dir" 2>/dev/null; then
    marker="tmux-location-refresh-marker-$(hostname -s 2>/dev/null || echo unknown)"
    # exec -a renames argv[0] so `pkill -f tmux-location-refresh-marker` finds it.
    # </dev/null detaches stdin so the worker outlives parent without holding pipes
    # (mirrors docs/solutions/code-quality/claude-code-hook-stdio-detach.md).
    ( exec -a "$marker" bash "$self" --refresh ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
fi

exit 0
