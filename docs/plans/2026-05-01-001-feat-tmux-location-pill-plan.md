---
title: "feat: Add city/region location segment to tmux status-right pill"
type: feat
status: active
date: 2026-05-01
deepened: 2026-05-01
---

# feat: Add city/region location segment to tmux status-right pill

## Summary

Add a city/region segment to the existing tmux status-right time/date pill so it reads `Sample City, ST · 3:24 PM · May 01` on the personal Mac and `Helsinki, Finland · 3:24 AM · May 02` on the VPS. Implementation is one new cross-platform shell script (`tmux/scripts/location.sh`) that resolves the city/region via CoreLocation on Darwin (the `corelocationcli` Homebrew **cask** — installs the binary as `CoreLocationCLI`, capitalized) and IP geolocation on Linux (`ipinfo.io` / `ip-api.com` over `curl + jq`), backed by a TTL cache outside the repo with async background refresh; `tmux/tmux.display.conf`'s `status-right` is rewritten to inject the segment, and the pill stays a single visual unit with the same blue/green palette.

---

## Problem Frame

The status-right pill currently shows just `%-I:%M %p · %b %d`. The user moves between locations (home, work, occasional travel) and runs an inner tmux on a Hetzner-FI VPS. Showing the current city/region in the pill would give a glanceable "where am I right now" that also doubles as a clear LOCAL-vs-VPS visual differentiator beyond the existing palette split. There is no existing surface for this in the dotfiles repo — fresh build.

---

## Requirements

- R1. Render a city/region segment in the existing tmux status-right pill in the form `City, Region` for US (e.g. `Sample City, ST`) and `City, Country` for international (e.g. `Helsinki, Finland`).
- R2. Use Apple CoreLocation (the `corelocationcli` Homebrew **cask**, which installs the binary as `CoreLocationCLI`) as the source on macOS for neighborhood-level precision.
- R3. Use IP geolocation as the source on the Linux VPS — Hetzner-FI naturally returns Helsinki/Finland; no special-case hardcode.
- R4. Never block or break the status bar. Network failure, missing dependency, missing permission, or empty cache must all silently fall through to a last-known value or an empty segment.
- R5. Keep the location data out of the repo. The cache lives at `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/`, which Dotbot does not manage.
- R6. Refresh aggressively enough to track travel on Mac (~30 min TTL) and lazily on the VPS (~24 h TTL — it doesn't move).
- R7. Preserve the existing `continuum_save.sh` invocation in `status-right`. Rewrites that drop it silently kill tmux-continuum auto-saves.

---

## Scope Boundaries

- No latitude/longitude, timezone, weather, altitude, or any non-place data in the pill.
- No "location changed" notification, log, or history.
- No sub-city precision (street, neighborhood-name beyond CoreLocation's locality field) — CoreLocation's `%locality` is the floor.
- No VPS-specific override hack hardcoding "Helsinki" — IP geolocation handles it.
- No work Mac path. The Mac CoreLocation flow targets the personal Mac. Work Mac will silently no-op on missing `corelocationcli` (graceful) until the user opts in by installing it there too. The corporate proxy + TCC permission story is out of scope for this plan.
- No tests in a test framework — this repo has no shell-script test runner. Verification is behavioral via the live status bar.

### Deferred to Follow-Up Work

- Migrating the Apple CoreLocation permission setup into the install pipeline (one-shot pre-flight invocation with a clear "grant Location Services to iTerm" message). For now, install ships the dependency and a documentation entry; the user resolves the Gatekeeper + TCC prompts manually on first use.
- Adding `corelocationcli` to the work Mac. Same plan applies; just left for a follow-up commit when the user is ready.

### Deferred from doc review (advisory FYI)

These items were flagged at anchor 50 (advisory) by the doc-review pass on 2026-05-01. They are not blockers and do not warrant plan-time decisions, but worth keeping in mind during implementation or a future hardening pass:

- **tmux `#()` async refresh semantics vary by version.** Modern tmux (3.4+) refreshes `#()` substitutions in the background; older tmux blocks status redraw on the script's return. Both Mac (Homebrew, current) and Ubuntu 24.04 (apt, 3.4) are above the floor — confirm `tmux -V` ≥ 3.4 on both before relying on the empty-cold-cache UX. No version assertion in the plan today.
- **`continuum_save.sh` verification on the VPS.** The U3 verification step (`last`-file mtime advances after status-right rewrite) should run on **both** Mac and VPS independently — the rewrite affects both via the shared config file, and a regression on one would not surface from the other.
- **Exact path to tmux-continuum's `last` file.** Currently `~/.config/tmux/resurrect/last`; the U3 prose says "or wherever continuum writes" because the path is plugin-internal. Acceptable; if continuum changes the path, the verification step's catch-rate degrades silently.
- **TCC blast radius.** Granting Location Services to iTerm2 authorizes every process spawned under it (any shell, npm postinstall, plugin) to read CoreLocation without a further prompt. Captured in the U1 solutions doc as a least-privilege note; not architectural.
- **Cap glyph behavior at wider pill widths under iTerm transparency.** The `iterm-transparency-foreground-glyphs-opaque-2026-05-01.md` doc was written for the current narrower pill; the same recipe should hold at 70-cell pills, but worth eyeballing on first attach after U3 lands.
- **Work Mac scope language.** Scope Boundaries says "no work Mac path" but the script's `uname=Darwin` branch will run on both Macs; the work Mac no-ops because `CoreLocationCLI` isn't installed there. Behavior is correct; the wording could mislead.
- **Doubled-separator concern in long-string test scenario** (raised by feasibility review): investigated and dismissed. The pill format uses `<location-with-trailing-space-separator>%-I:%M %p · %b %d` — the script emits one trailing `· ` and the format adds none before time, so the rendered pill has exactly one `·` between location and time. If a tester manually injects a string that already has the trailing separator, the result is correct; injecting without the separator produces no separator. Either way, no doubling.

---

## Context & Research

### Relevant Code and Patterns

- `tmux/tmux.display.conf:73-75` — current `status-right` definition. Inlines `#($XDG_CONFIG_HOME/tmux/plugins/tmux-continuum/scripts/continuum_save.sh)` (silent side-effect call) and renders `%-I:%M %p · %b %d` inside a rounded pill with Powerline Extra Symbols caps `U+E0B6` / `U+E0B4`. `status-right-length 40` at line 78 will need to bump.
- `tmux/scripts/save-window-meta.sh` — strict-mode reference (`set -euo pipefail`, atomic `mktemp` + `mv`). Useful pattern for the cache-write codepath.
- `tmux/scripts/restore-window-meta.sh` — silent-noop reference (`set -u` only, early `[ -f "$meta" ] || exit 0` exit, `command -v jq >/dev/null 2>&1 || exit 0`). **This is the style match for the hot-path read.** Status-bar scripts that fail loud break every redraw.
- `claude/hooks/tmux-attention.sh` — prior art for a marker-tagged disowned background loop with a sentinel-based cleanup gate. Useful template for the async refresh worker.
- `helpers/install_packages.sh` — Linux dep list (`apt-get install -y`); `curl` and `jq` already present (line 23). No additions needed for the IP path.
- `brew/Brewfile` — formula list above, casks at the bottom (line ~99 onward, alongside `docker-desktop` and `git-credential-manager`). The `corelocationcli` Homebrew package is a **cask**, not a formula — declare with `cask "corelocationcli"` in the casks section, alphabetically among the other casks. (Verify with `brew info corelocationcli` — the source line names `homebrew-cask`.)
- `install.conf.yaml:82-83` and `install-linux.conf.yaml:81-82` — both Dotbot configs explicitly enumerate each tmux script. **Easy miss:** forgetting the Linux config means the script never reaches the VPS.
- `zsh/zshenv:8` — exports `XDG_CACHE_HOME=$HOME/.cache`. The `:-$HOME/.cache` fallback in the script handles tmux's `run-shell` contexts that may not source zshenv.

### Institutional Learnings

- `docs/solutions/code-quality/tmux-format-hex-mangled-by-single-char-escape-2026-04-21.md` — every hex inside any `#{?...}` ternary in `status-right` must be `##RRGGBB`, never bare `#RRGGBB`. Applies if the rewrite introduces a stale-cache visual indicator or any new ternary.
- `docs/solutions/tmux/continuum-auto-save-dies-after-config-reload.md` — keep the `continuum_save.sh` invocation in the rewritten `status-right`. R7 above codifies this.
- `docs/solutions/best-practices/iterm-transparency-foreground-glyphs-opaque-2026-05-01.md` — under iTerm transparency, foreground glyphs render opaque. Match the existing pill cap recipe (cap glyph `fg = pill bg color, bg = bar default`); don't invent new tones.
- `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md` — if a new pin/marker glyph is introduced (e.g., `nf-fa-map_marker` U+F041), insert via Python heredoc with explicit codepoints, then `xxd` the bytes. Edit/Write/Bash argv strips PUA codepoints.
- `docs/solutions/code-quality/python-fstring-brace-collapse-breaks-format-strings-2026-04-29.md` — do not regenerate `status-right` via any f-string-style helper; nested `#{?...}` ternaries lose closers. Hand-edit.
- `docs/solutions/runtime-errors/tmux-attention-hook-race-condition-and-askuserquestion-state-2026-04-19.md` — async refresh workers must gate cleanup on a sentinel-still-exists check and tag the loop with a unique marker (`tmux-location-refresh-marker-<host>`) for `pkill` recovery.
- `docs/solutions/cross-machine/sync-vps-dry-run-previews-current-head.md` — VPS sync via `.github/workflows/sync-vps.yml` runs `./install` on the remote on manual trigger. Dry-run mode previews against the current HEAD on the VPS, not the pending PR; expect the symlink change to be invisible in dry-run output.

### Slack / Organizational Context

Not gathered — personal-machine feature, no org dimension.

### External References

Not gathered — `corelocationcli` and `ipinfo.io` / `ip-api.com` are well-documented, no security or payments risk, user signaled ship-mode.

---

## Key Technical Decisions

- **CoreLocation on Mac, IP geolocation on Linux.** CoreLocation gives neighborhood-level precision on the Mac (the user's primary surface and the only one that travels). IP geolocation is sufficient for the VPS, which is a fixed Hetzner-FI host. Trade-off accepted: first run on Mac requires granting Location Services to iTerm2 (or whichever tmux ancestor) — see Risks. *(see also: solo-mode synthesis confirmed by user with "I choose CoreLocation on Mac + IP on VPS")*

- **One cross-platform script, branched on `uname`.** Repo convention is `if [ "$(uname)" = "Darwin" ]; then ... else ... fi` (`helpers/install_packages.sh:7`, `helpers/install_fonts.sh:4`, others). No `[[ "$OSTYPE" == "darwin"* ]]`. Single script avoids two install-pipeline entries.

- **TTL cache + async refresh.** Hot path reads instantly from a cached value; staleness triggers a detached background fetch tagged with a unique marker so a leak can be `pkill`ed. `status-interval 1` means the script is invoked every second — synchronous fetch on the hot path is non-negotiable. Pattern mirrors `claude/hooks/tmux-attention.sh`.

- **Refresh lock prevents storm.** Once a stale read kicks an async refresh, subsequent stale reads in the same second-tick must not stack. A lock file (`mkdir -p`-based, atomic on POSIX) gates the spawn. The refresh worker removes the lock as its last act.

- **First-run behavior is empty, not blocking.** When no cache exists at all, the hot path returns an empty string (segment collapses) and kicks the async fetch. Pill populates on the next status interval after the fetch completes (~1–2s later). No bounded synchronous fallback — keeps the model uniform.

- **Cache outside the repo, in XDG.** `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/` per repo's no-hardcoded-paths rule. No Dotbot involvement — script `mkdir -p`'s on first run, same as `save-window-meta.sh:12`.

- **Format rule.** ISO country code `US` → `${city}, ${region}` (2-letter region code, US-only). Anything else → `${city}, ${country}` (full country name). On Mac, CoreLocation's reverse geocoding returns a full country name via `%country`, so no map needed. On Linux/VPS the `ipinfo.io` response returns a 2-letter country code only, so the script carries a small inline `case` map of likely countries (US, CA, MX, GB, FI, DE, FR, ES, IT, JP, AU, NZ, NL, SE, CH, DK, NO, IS) → full name, with a fallback to the 2-letter code for un-mapped countries. Map is intentionally short; expand on demand.

- **IP-geo source: `https://ipinfo.io/json` (HTTPS).** Picked over the HTTP-only free tier of `ip-api.com` because the response is fed into a tmux format string (see "Output sanitization" below) — eliminating the response-forgery vector at the wire layer is cheaper than relying solely on sanitization. ipinfo.io's free tier is 50k requests/month; the VPS at 24h TTL uses ~30/month, far inside the limit.

- **Output sanitization.** Before writing the cache file, the worker strips characters that re-enter tmux's format parser when the cache value is interpolated by `#(script)`: `#`, `[`, `]`, `{`, `}`, `(`, `)`, plus control bytes and quotes. Filter shape: `result=$(printf '%s' "$raw" | tr -d '#[]{}()`"'"'\n\r' | tr -cd '[:print:]')`. This is an integrity guard — a forged or malicious API response cannot smuggle a tmux format directive (e.g., `#(touch /tmp/pwned)`) or a shell metachar through the pill. The same sanitization runs for both the Darwin and Linux branches; CoreLocation output is also untrusted in principle (e.g., a city name with a Unicode quirk).

- **Output length cap.** Cap the resolved string at 64 chars before atomic write. Anything longer is treated as a malformed/forged response and the write is skipped (last-known stays). Belt-and-suspenders against a degenerate API returning multi-megabyte payloads.

- **Location segment length cap (display).** The script truncates the formatted segment to ≤24 visible chars before emitting (preserving city, then `, region|country`, then trailing `· `). Prevents long city names from eating the time/date suffix via tmux's right-side truncation. `status-right-length 70` then sits comfortably above the worst combined case.

- **Render position.** Prepended to the existing time/date pill, sharing the same blue/green pill background and `·` separators — one visual unit, not a separate pill. Pill format becomes `<location-segment-with-trailing-separator-or-empty>%-I:%M %p · %b %d`. The script emits `City, State · ` (with one trailing `· ` separator and one trailing space) when populated and `` (empty) when not, so tmux doesn't need a ternary to suppress the leading separator. No leading separator is added by the format itself, so empty location collapses cleanly with no doubled separator.

- **Transition + stale-while-refreshing visual states.** Cold-cache → populated transitions render as a single-frame width jump (~1–2s after first attach); accepted as glanceable, not real-time — no fade, no placeholder dash. Stale-while-refreshing displays the previous value during the seconds the worker fetches; accepted with no visual marker (no dim color, no `?` suffix). The pill is a glance surface, not a status indicator. Both states are explicit non-decisions to prevent unsolicited indicator implementations.

- **Pill vs segment terminology.** *Pill* = the rounded blue/green visual unit (cap glyphs + bold-on-color body). *Segment* = a logical chunk inside the pill (location segment, time segment, date segment). The location *segment* lives inside the existing time/date *pill*; they share one pill, three segments.

- **`status-right-length` bump from 40 to 70.** Empirically: `Helsinki, Finland · 3:24 AM · May 02` is ~37 chars + cap glyphs + padding ≈ 50–55 visible cells; 70 buys headroom for longer city/region combos (e.g. `Cameron Park, CA` plus the full date in winter when months expand).

- **No new tmux user option.** The script returns the formatted string directly via `#(script)`. No `@location_label` user option, no `set-option` writes from inside the worker — sidesteps the bare-index-target gotcha entirely.

---

## Open Questions

### Resolved During Planning

- **CoreLocation vs IP geo on Mac.** User chose CoreLocation on Mac.
- **Where to put it.** Integrated into the existing time/date pill, not a separate pill.
- **Cache location.** `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/`.
- **TTL values.** 30 min Mac, 24 h VPS.
- **Failure mode.** Silent fall-through to last-known or empty.

### Deferred to Implementation

- **Exact `CoreLocationCLI` `-format` token string.** The cask's binary flag list is the source of truth; implementer should run `CoreLocationCLI -h` on the Mac to confirm token names (`%locality`, `%administrativeArea`, `%country`, `%isoCountryCode`) before writing the parse path.
- **`status-right-length` final value.** 70 is a reasonable starting point; bump if `tmux display-message -p '#{status-right}'` shows truncation in the longest realistic city case (the script's 24-char location cap + 22-char time/date suffix + chrome should fit comfortably).
- **Refresh-worker tagging convention.** Borrow shape from `claude/hooks/tmux-attention.sh`; exact marker string can be settled at write time.
- **ISO-3166 map size on Linux.** Initial map covers ~18 countries. Expand if a 2-letter code shows up in the pill; treat as a runtime tuning rather than upfront completeness.

---

## Implementation Units

- U1. **Add `corelocationcli` to Brewfile and document the macOS Location Services permission flow**

**Goal:** Ship the macOS dependency and the user-facing documentation needed to grant Location Services so the script can resolve a city on the Mac.

**Requirements:** R2

**Dependencies:** None.

**Files:**
- Modify: `brew/Brewfile`
- Create: `docs/solutions/best-practices/macos-location-services-tcc-prompt.md`

**Approach:**
- Insert `cask "corelocationcli"` in the **casks section** of `brew/Brewfile` (alongside `docker-desktop` and `git-credential-manager`, alphabetically among casks). Note: this is a cask, not a formula — `brew "corelocationcli"` will fail with `Error: No available formula`.
- New solutions doc captures three first-run gates the user hits in order:
  1. **Gatekeeper notarization.** First invocation of `CoreLocationCLI` is blocked by Gatekeeper ("cannot verify the developer"). User opens System Settings → Privacy & Security → Security and clicks "Open Anyway." This gate is *separate from and prior to* the Location Services TCC prompt, and the cask's upstream README confirms it. Document this step first because it's the one a user can mistake for "the cask is broken."
  2. **Location Services TCC prompt.** After Gatekeeper approval, the second invocation triggers the TCC prompt. Which app receives it: the GUI ancestor of the tmux server — typically iTerm2; if tmux was started under a different parent, the prompt attributes there.
  3. **Verification.** System Settings → Privacy & Security → Location Services should show iTerm2 (or the actual ancestor) with the toggle ON.
- Workaround when the TCC prompt does not surface (e.g., tmux was auto-attached at shell start before iTerm2 was the parent): one-shot `CoreLocationCLI` invocation from a fresh iTerm2 window outside tmux — note the binary is capitalized even though the cask name is lowercase.
- TCC blast-radius note: granting Location Services to iTerm2 authorizes every process spawned under it (any shell, npm postinstall, plugin) to read CoreLocation without a further prompt. Worth keeping in mind when running untrusted code in that terminal; not a blocker for this plan.
- Doc frontmatter: `problem_type: best_practice`, `module: tmux`, dated 2026-05-01.

**Patterns to follow:**
- `brew/Brewfile` alphabetical ordering convention (formulas grouped, casks at the bottom).
- `docs/solutions/best-practices/iterm-transparency-foreground-glyphs-opaque-2026-05-01.md` for solutions-doc frontmatter shape and prose style.

**Test scenarios:**
- *Test expectation: none — pure config + documentation. Verification is that `brew bundle check --file=brew/Brewfile` reports the file satisfied after a `brew install corelocationcli`, and that the doc renders cleanly in a markdown previewer.*

**Verification:**
- `brew bundle install --file=brew/Brewfile` installs `corelocationcli` without error on Mac.
- `CoreLocationCLI` (capitalized binary) is callable from the shell after the user clears the Gatekeeper gate (System Settings → Privacy & Security → Security → "Open Anyway") and grants Location Services. First-run will fail until both gates are passed; this is expected and documented in the new solutions doc, not a regression.
- The new solutions doc reads end-to-end without unresolved cross-links.

---

- U2. **Create `tmux/scripts/location.sh` and wire it into both Dotbot configs**

**Goal:** Cross-platform location resolver that returns the formatted city/region string (with trailing separator) on cache hit, returns last-known on cache stale, and kicks an async refresh; never blocks the status bar.

**Requirements:** R1, R3, R4, R5, R6

**Dependencies:** U1 (so the Mac path has `CoreLocationCLI` on PATH; Linux deps `curl` and `jq` already present in `helpers/install_packages.sh:23` — verified by repo-research, no additions to `apt-get install -y` needed).

**Files:**
- Create: `tmux/scripts/location.sh`
- Modify: `install.conf.yaml` (add symlink line in the `link:` block alongside the other tmux script entries, line ~82)
- Modify: `install-linux.conf.yaml` (add the *same* symlink line in its `link:` block, ~line 81)

**Approach:**
- Shebang `#!/usr/bin/env bash`, mode `set -u` (silent-noop style; do **not** use `set -e` on the hot path — match `restore-window-meta.sh`).
- Header comment: 2–3 lines of purpose + invocation (`# Invoked from tmux status-right; emits "City, Region · " or empty.`).
- Subcommand surface: bare invocation = "read from cache, optionally kick async refresh, emit string"; `$0 --refresh` = the worker entry point (writes cache atomically, removes the lock).
- Platform branch: `case "$(uname)" in Darwin) source=corelocation ;; *) source=ipgeo ;; esac`.
- Cache path: `cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location"`, cache file: `$cache_dir/value`, lock file: `$cache_dir/.refresh.lock`.
- TTL: 1800s (30 min, per R6) on Darwin, 86400s (24 h, per R6) elsewhere.
- Hot path:
  1. `mkdir -p "$cache_dir"` (silent if already present).
  2. If `value` exists, `cat` it (single line, no newline added downstream).
  3. If `value` is missing OR `mtime + ttl < now`: before attempting to claim the lock, check whether an existing lock dir is older than 60s (`find "$lock" -maxdepth 0 -type d -mmin +1 2>/dev/null`) and `rmdir` it if so — this self-heals a crashed worker that left a stale lock. Then attempt `mkdir "$lock"` (atomic on POSIX); if it succeeds, spawn the worker: `( "$0" --refresh; rmdir "$lock" 2>/dev/null ) >/dev/null 2>&1 & disown`. Tag the worker with a `bash -c 'exec -a tmux-location-refresh-marker-$HOSTNAME ...'` shape (or the equivalent marker pattern used in `claude/hooks/tmux-attention.sh`) so leaked workers can be `pkill -f tmux-location-refresh-marker` recovered.
  4. Exit 0.
- Worker (`--refresh`):
  - Darwin path: `CoreLocationCLI -format <tokens>` (capitalized binary) returns `locality + administrativeArea + isoCountryCode + country`. Format rule: `isoCountryCode == US` → `${locality}, ${administrativeArea}`, else → `${locality}, ${country}` (full country name from CoreLocation's reverse geocoding).
  - Linux path: `curl -sS --max-time 4 https://ipinfo.io/json | jq -r '.city + "|" + .region + "|" + .country'` (HTTPS, no auth). Parse fields; if `country == "US"`, format as `${city}, ${region}`; else look up the 2-letter `country` code in the inline `case` map and format as `${city}, ${country_full}` (or `${city}, ${country_code}` if un-mapped).
  - **Sanitize** the resolved string: strip tmux-format-significant characters (`#`, `[`, `]`, `{`, `}`, `(`, `)`), shell-significant characters (backticks, `$`, double/single quotes), control bytes, and newlines. Use `tr -d` + `tr -cd '[:print:]'` as documented in the Key Technical Decisions › Output sanitization entry.
  - **Length-cap** the sanitized result at 64 chars; if longer, treat as malformed and exit without writing.
  - **Display-truncate** the sanitized, length-capped result to ≤24 visible chars (preserve city; truncate region/country with an ellipsis if needed). Append the trailing `· ` separator.
  - Atomic write: `tmp=$(mktemp "$cache_dir/value.XXXXXX") && printf '%s' "$result_with_separator" > "$tmp" && mv "$tmp" "$cache_dir/value"`. Pattern matches `save-window-meta.sh`.
  - On any error (missing dep, network failure, malformed JSON, length over 64, CoreLocation unavailable, Location Services denied): exit silently without writing. Last-known stays in place; pill keeps showing yesterday's location until network or permission heals.
- Dependency probes (silent): `command -v CoreLocationCLI >/dev/null 2>&1 || exit 0` on Darwin (binary is capitalized), `command -v curl >/dev/null 2>&1 || exit 0` and `command -v jq >/dev/null 2>&1 || exit 0` on Linux. Exit 0 on missing tools, never 1 — `set -e` upstream would kill the bar.
- Both Dotbot configs get a new line in their existing `link:` blocks: `~/.config/tmux/scripts/location.sh: tmux/scripts/location.sh`. **Both files must be edited in the same commit.** A test reader of the diff should be able to find the new symlink in both configs without searching.

**Execution note:** The repo has no shell-script test framework. Verification is behavioral — exercise each scenario manually after the symlink is in place.

**Patterns to follow:**
- `tmux/scripts/restore-window-meta.sh` — silent-noop hot path, `command -v` guards, `set -u`, no `set -e`.
- `tmux/scripts/save-window-meta.sh` — atomic write pattern (`mktemp` + `mv`), `mkdir -p` of cache dir.
- `claude/hooks/tmux-attention.sh` — marker-tagged disowned worker, sentinel-based cleanup gate.
- `helpers/install_packages.sh:7` — `if [ "$(uname)" = "Darwin" ]; then ... fi` as the platform-branch idiom.

**Test scenarios:**
- *Happy path (Mac, cold cache):* Run `tmux/scripts/location.sh` from a Mac shell. First call returns empty (no cache yet) and spawns a worker. Within 2 seconds, `cat ~/.cache/tmux-location/value` shows `Sample City, ST · ` (or whatever the user's actual locality is).
- *Happy path (Mac, warm cache):* Subsequent calls within the TTL window return instantly from cache. Time the call: should be <50 ms.
- *Happy path (VPS, cold cache):* Same flow on the VPS. After a few seconds the cache contains `Helsinki, Finland · ` (or whatever Hetzner-FI's actual public IP geolocates to).
- *Edge case (cache stale):* Manually `touch -t 202601010000 ~/.cache/tmux-location/value`. Next call returns the existing value AND spawns a worker that overwrites the file with a fresh value. Lock dir appears briefly during the refresh, vanishes after.
- *Edge case (refresh storm):* Run the script in a tight loop (`for i in {1..30}; do ./location.sh; done`) with a stale cache. Verify only one worker process appears (`pgrep -f tmux-location-refresh-marker | wc -l` ≤ 1 at any moment). The lock is the gate.
- *Error path (missing `CoreLocationCLI` binary on Mac):* Temporarily `brew uninstall --cask corelocationcli` (cask name lowercase, package operation), run the script. Returns existing cached value (or empty if no cache); no error output, no `set -e` propagation. Re-install to recover.
- *Error path (Location Services denied on Mac):* Toggle iTerm2 off in System Settings → Privacy & Security → Location Services. Worker exits silently without writing. Pill keeps showing last-known. (Re-grant to recover; see U1's solutions doc for the procedure.)
- *Error path (network down on VPS):* Block outbound HTTPS via `iptables -A OUTPUT -p tcp --dport 443 -j REJECT` (or use `unshare -n` for a no-network namespace). Worker exits silently; pill keeps showing last-known.
- *Edge case (corrupted JSON response):* Pipe a deliberately malformed body into the parse step (e.g., temporarily redirect `curl` via a wrapper that returns `{"city":"<not-json"`). Script exits silently without writing.
- *Edge case (sanitization — tmux format-string injection):* Force a malicious cache value: `printf '%s' '#(touch /tmp/pwned) · ' > ~/.cache/tmux-location/value`. Reload the pill. Confirm `/tmp/pwned` does NOT exist after the next status redraw — the worker re-runs and rewrites the cache through the sanitization filter, stripping the `#(...)` payload to the printable-only remainder. Worker-side verification: pipe a synthetic city name `'Hax #[bg=red]City'` into the worker's parse step and confirm the resulting cache value contains no `#`, `[`, `]`, `{`, `}`, `(`, `)`, backticks, or quotes.
- *Edge case (length cap — degenerate response):* Force a synthetic API response where the parsed city is a 200-char string. Worker treats it as malformed and exits without writing the cache. Last-known stays.
- *Edge case (display truncate — long city):* Force a synthetic `locality` longer than 24 chars (e.g., `Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch`). The cache value is truncated to ≤24 visible chars + the trailing `· ` separator. Pill renders the truncated form, time/date suffix intact.
- *Edge case (un-mapped country code):* On the Linux path, force a country code that the inline ISO-3166 map doesn't include (e.g., `XK` for Kosovo). Pill falls back to `City, XK` form. No error.
- *Edge case (stale lock self-heal):* Manually create `~/.cache/tmux-location/.refresh.lock`, set its mtime to 90 seconds ago. Run the script with a stale cache. Verify the lock is removed and a new worker spawns. Confirms the 60s TTL self-heal is in effect.
- *Integration scenario:* From a live tmux session, `tmux display-message -p '#($XDG_CONFIG_HOME/tmux/scripts/location.sh)'` returns the same string the cache file contains. Confirms tmux's `run-shell` context resolves `$XDG_CONFIG_HOME` and the script's deps consistently with how the status bar will invoke it.

**Verification:**
- The script returns within 50 ms on cache hit.
- Stale cache triggers exactly one async refresh per stale-window, regardless of how often the script is invoked.
- All error paths silently fall through; nothing prints to stderr that tmux would render.
- Both Dotbot configs symlink the script. Run `./install --dry-run` on Mac and `./install --dry-run` (or the Linux config equivalent) and confirm both list the new symlink under "Would create symlink".

---

- U3. **Rewrite `tmux/tmux.display.conf` `status-right` to inject the location segment and bump `status-right-length`**

**Goal:** Surface the resolver's output in the status-right pill while preserving the existing pill chrome, the `continuum_save.sh` hook, and the LOCAL/VPS color split.

**Requirements:** R1, R7

**Dependencies:** U2 (the script must exist and be symlinked into `~/.config/tmux/scripts/` before the config calls it).

**Files:**
- Modify: `tmux/tmux.display.conf` (lines 73-75 for `status-right`, line 78 for `status-right-length`)

**Approach:**
- Inject `#($XDG_CONFIG_HOME/tmux/scripts/location.sh)` immediately before the `%-I:%M %p` token, *inside* the same pill body so the location, time, and date share one rounded shell. Resulting body shape (directional, not literal): `<continuum-side-effect><left-cap><pill-bg-fg-bold> <location-with-trailing-separator>%-I:%M %p · %b %d <right-cap>`.
- The script emits its own trailing ` · ` separator when populated and emits empty when not — no tmux-side ternary needed to suppress a leading separator on cold cache.
- Preserve the `continuum_save.sh` invocation verbatim at the start of the format string. The location call goes after it.
- Preserve the `#{?#{==:#S,vps},##33843A,##2563EB}` LOCAL/VPS color ternary. Hex codes already use the `##` escape; do not regress.
- Bump `status-right-length` from 40 to 70 at line 78.
- Do **not** generate the new format string via Python f-strings or any `{}`-interpolation helper. Hand-edit (the f-string brace-collapse rule in `python-fstring-brace-collapse-breaks-format-strings-2026-04-29.md`).

**Technical design:** *(directional only, not literal — exact byte-for-byte content settles at write time)*

```
status-right body shape:
[continuum_save side-effect]
[left-cap glyph: fg=pill-bg, bg=default]
[pill-body open: bg=pill-bg, fg=#FFFFFF, bold]
  [#(location.sh) — emits "City, Region · " or empty]
  %-I:%M %p · %b %d
[pill-body close: trailing space]
[right-cap glyph: fg=pill-bg, bg=default]
```

**Patterns to follow:**
- Existing `tmux/tmux.display.conf:73-75` structure — follow the cap+body+cap shape exactly.
- `tmux/tmux.display.conf:55` for the status-left LOCAL/VPS color ternary; reuse the same hex codes and the same `##` escape convention.

**Test scenarios:**
- *Happy path (Mac, cache populated):* Reload tmux config (`tmux source ~/.config/tmux/tmux.conf`). Status-right pill shows `<your city>, <your region> · 3:24 PM · May 01` (or current time/date). The pill body is one continuous blue rounded shell.
- *Happy path (Mac, cache empty):* Delete `~/.cache/tmux-location/value` and reload. Pill briefly shows `3:24 PM · May 01` with no leading location segment, then within ~2s the location appears as the worker writes the cache.
- *Happy path (VPS):* On the VPS, the same pill renders `Helsinki, Finland · 3:24 AM · May 02` in the green VPS palette (12-hour AM/PM format inherited from the existing `%-I:%M %p`, same on both hosts). Color ternary still resolves correctly.
- *Edge case (long location, post-truncation):* The script's 24-char display cap (U2) means the cache will never contain more than ~26 visible chars (location + ` · `). To stress the pill, manually inject a string at the cap boundary: `echo "Saint-Pierre-et-Mique… · " > ~/.cache/tmux-location/value`. Confirm `tmux display-message -p '#{status-right}'` shows no further truncation eating the time/date suffix. If it does, bump `status-right-length` from 70 to 80.
- *Integration scenario:* `tmux-continuum` auto-saves continue to fire after the rewrite. Verify by checking the modification time on `~/.config/tmux/resurrect/last` (or wherever continuum writes) — it should advance over a 30-minute window after the rewrite. Catches accidental drops of the `continuum_save.sh` hook.
- *Edge case (PREFIX/COPY/SYNC modes):* Press the prefix key, enter copy mode, and toggle `synchronize-panes`. Status-left's mode pills appear and disappear correctly; status-right's location+time pill is unaffected.

**Verification:**
- The pill renders with location, time, and date in one visual unit.
- LOCAL and VPS color split is preserved on both hosts.
- `tmux-continuum` auto-saves still fire (`last`-modified file mtime advances).
- No tmux startup error, no format-string warning in `tmux show-messages`.
- `status-right-length 70` accommodates the longest realistic city/country string.

---

## System-Wide Impact

- **Interaction graph:** The script is invoked every second from `status-right` (`status-interval 1`). The async worker runs detached on the host whose tmux is reading. No interaction with the inner-VPS tmux beyond the same script running on the VPS host.
- **Error propagation:** Errors stay inside the script. Hot path always exits 0 by design; worker errors are swallowed (last-known stays). Nothing escapes to tmux's stderr.
- **State lifecycle risks:** Cache file write is atomic (`mktemp` + `mv`). Lock-file leak is recoverable via `rmdir` in the worker's tail, via the 60s lock-TTL self-heal codified in U2's hot path, and via `pkill -f tmux-location-refresh-marker` if both fail.
- **API surface parity:** No external API surface introduced for the dotfiles repo. Just a new script invoked from one config file.
- **Integration coverage:** The tmux `run-shell` context (no zsh init) must resolve `$XDG_CONFIG_HOME` and find `CoreLocationCLI` / `curl` / `jq` on PATH. Verify via `tmux display-message -p '#($XDG_CONFIG_HOME/tmux/scripts/location.sh)'` from a live session before declaring the unit done.
- **Unchanged invariants:** The `continuum_save.sh` invocation, the `##` hex-escape pattern in status-left's ternaries, the LOCAL/VPS color split, and the active-vs-inactive window-format whitespace symmetry rule (`docs/solutions/runtime-errors/`-tracked) all stay as-is.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| First-run on Mac shows no location because Gatekeeper or the TCC prompt didn't surface or wasn't accepted. | U1's solutions doc captures the two-gate recovery path: System Settings → Privacy & Security → Security → "Open Anyway" (Gatekeeper), then accept the Location Services TCC prompt on the second invocation. Documented; not automated. |
| `corelocationcli` Homebrew cask goes unmaintained or is renamed. | Verify the cask exists at write time (`brew info corelocationcli` — source should show `homebrew-cask`). If gone, fall back to an alternative (the `whereami` tool, or a small Swift binary) and update U1 accordingly. Worth checking before the implementer types the Brewfile line. |
| `ipinfo.io` rate-limit or free-tier deprecation. | TTL of 24h on VPS = ~30 calls/month, far below the 50k/month free-tier limit. If the API disappears, swap providers — the inline ISO-3166 map keeps the script's contract stable across providers. |
| Forged or malicious API response. | HTTPS at the wire layer (ipinfo.io) prevents on-path forgery; output sanitization (strip `#[]{}()`, quotes, control bytes) defangs anything malformed at the source; 64-char length cap rejects degenerate payloads. Three layers of defense. |
| Refresh-storm bug — lock file isn't released, blocking all future refreshes silently. | U2's hot path includes a 60s TTL self-heal (`find "$lock" -mmin +1` removes a stale lock before claiming). Header-comment documents the `pkill -f tmux-location-refresh-marker` recovery if the self-heal isn't enough. |
| Rewriting `status-right` accidentally drops `continuum_save.sh`. | R7 codifies the requirement. U3's verification step explicitly checks that auto-saves still fire after the rewrite. |
| Long city names exceeding the pill width. | Script-side 24-char display cap (U2) prevents location from eating time/date. `status-right-length 70` provides headroom; bump to 80 if a real-world case overflows. |
| Privacy: the cache file contains the user's current city. | Cache lives at `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/`, outside the repo. R5 codifies. The user's `~/.cache/` is local-only; it is not synced to the VPS or anywhere else. The `dotfiles` GitHub repo never sees it. |

---

## Documentation / Operational Notes

- **Branch policy.** Per project CLAUDE.md ("Always create a new branch when picking up a ticket from the board") and the user's confirmation rule ("ask before behavior changes"), `ce-work` should branch off master and open a PR rather than landing direct-to-master. The Brewfile entry, new script, Dotbot config edits, and tmux config rewrite are all behavior changes; the new solutions doc alone would qualify for direct-commit, but it ships in the same PR as the implementation.
- **Commit shape inside the PR.** All three units can be one commit, or U1 + (U2+U3) as two commits. The hard constraint from U2 — both Dotbot configs (`install.conf.yaml` and `install-linux.conf.yaml`) must land in the **same commit** — applies regardless of how the units split. Don't put the Mac symlink in commit A and the Linux symlink in commit B; mid-PR builds on either machine would diverge.
- **VPS deploy sequence.** New tmux scripts reach the VPS only via `.github/workflows/sync-vps.yml` manual trigger after merge. Coordinate: merge PR → trigger workflow → on first VPS refresh, the script populates the cache asynchronously over ~5 seconds, then the pill updates on next status-interval tick.
- **macOS first-run procedure.** After install, the user runs `CoreLocationCLI` (capitalized binary) once from iTerm2 (outside tmux), accepts the Location Services prompt, and verifies in System Settings → Privacy & Security → Location Services. Documented in U1's new solutions doc.
- **Compounding learning.** After this lands, capture the Location Services / TCC permission flow as the solutions doc's `update_count` advances if the prompt routing differs from what's documented. The learnings agent flagged this as a current gap in `docs/solutions/`; U1 fills it but real-world surprises may refine it.

---

## Sources & References

- Origin: solo-mode synthesis (no upstream brainstorm doc; user request 2026-05-01).
- Related code: `tmux/tmux.display.conf:73-78`, `tmux/scripts/restore-window-meta.sh`, `tmux/scripts/save-window-meta.sh`, `claude/hooks/tmux-attention.sh`, `helpers/install_packages.sh`, `brew/Brewfile`, `install.conf.yaml`, `install-linux.conf.yaml`.
- Related learnings: see Context & Research › Institutional Learnings.
- External references: not gathered (skipped per Phase 1.2 — well-trod APIs, no security/payments risk).
