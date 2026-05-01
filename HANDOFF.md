# HANDOFF — 2026-05-01 (PDT)

Continuation of the 2026-04-30 → 2026-05-01 tmux iteration arc. Started with a release-notes drive-by and rolled into a full feature: city/region location segment in the tmux status-right pill, planned via `/ce-plan`, shipped via `/ce-work` (PR #55), reviewed via `/ce-code-review`, and compound-learned via `/ce-compound`. Merged + synced + verified working on both hosts.

## What We Built

### PR #55 — feat: tmux status-bar location pill (merged 2026-05-01T19:30Z)

5 commits on `feat/tmux-location-pill`, rebase-merged to master:

1. **`fa8cfd2` docs(plans)** — `docs/plans/2026-05-01-001-feat-tmux-location-pill-plan.md` (352 lines). Solo-mode synthesis, deepened by `ce-doc-review` (3 P0/P1 correctness blockers and a tmux format-injection vector resolved at plan time before any code shipped).
2. **`8015ca4` feat(brew)** — added `cask "corelocationcli"` to `brew/Brewfile` (cask, not formula — `brew "..."` errors). New `docs/solutions/best-practices/macos-location-services-tcc-prompt.md` documenting the Gatekeeper → TCC → verify recovery flow, including a "Debugging from the CLI" probe section and the TCC blast-radius note (granting Location Services to iTerm2 covers all child processes).
3. **`35fb637` feat(tmux)** — new `tmux/scripts/location.sh` (251 lines after fixes). Cross-platform: `CoreLocationCLI --format` on Darwin, `https://ipinfo.io/json | jq` on Linux. Inline ISO-3166 → name map for ~22 countries. TTL cache (30 min Mac, 24h VPS) at `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/`. Async refresh worker tagged via `exec -a tmux-location-refresh-marker-<host>` for `pkill` recovery. Atomic mkdir-based lock with 60s self-heal. Sanitization on **both** read and write paths strips tmux format chars (`#[]{}()`), shell metachars, control bytes; preserves multibyte UTF-8 (the `·` separator). 64-byte length cap. 24-char display truncation. `</dev/null` stdin detach for the worker. Both Dotbot configs (`install.conf.yaml` + `install-linux.conf.yaml`) symlink it in the same commit.
4. **`2f61d0c` feat(tmux)** — `tmux/tmux.display.conf` `status-right` rewrite. Injected `#($XDG_CONFIG_HOME/tmux/scripts/location.sh)` into the existing pill body (one rounded shell, three segments). Preserved the `continuum_save.sh` hook verbatim (R7), the LOCAL/VPS color ternary with `##` hex escapes, and the U+E0B6 / U+E0B4 cap glyphs (5 of each, before and after). Bumped `status-right-length` 40 → 70.
5. **`4b63182` fix(tmux)** — `/ce-code-review` round addressed two P0s, three P1s, and a bundle of P2 micro-perf consolidations. See "What Didn't Work" for the specific defects.

### Compound learning (post-merge, direct to master per docs carve-out)

- **`fc0c64a` docs(solutions)** — `docs/solutions/best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md` (197 lines). Captures the two distinct shell-scripting pitfalls surfaced by code review: the `read -r || return 0` short-circuit on EOF-without-newline and the `uname`-vs-`stat-f` collision when Homebrew `coreutils` is on PATH ahead of `/usr/bin`. Tied together by the meta-pattern (behavioral tests miss broken late-stage pipelines when an early stage short-circuits). Cross-references `brew-shellenv-clobbers-path-via-path-helper.md` (upstream PATH cause), `ssh-as-root-write-ownership-and-exit-propagation.md` (parallel exit-code-masking pattern), and `python-fstring-brace-collapse-breaks-format-strings-2026-04-29.md` (silent corruption family).

### VPS deploy + verify

- `gh workflow run sync-vps.yml --ref master --field dry_run=false` → run 25229778540 succeeded in 31s.
- SSH to `openclaw-prod`: confirmed `/root/.config/tmux/scripts/location.sh` symlink in place; ran `--refresh` synchronously to seed cache (returned `Helsinki, Finland · ` in ~1s); reloaded both `main` and `vps` tmux sessions; rendered status-right confirmed in green VPS palette `#33843A`. Pill is live.
- Mac side already verified end-to-end during code-review fix verification: cache contains real CoreLocation output for the user's actual locality, `tmux source-file` clean, `tmux-continuum` auto-saves still firing.

## Decisions Made

- **CoreLocation on Mac, IP geo on VPS** (user-confirmed at synthesis time). Trade-off accepted: neighborhood-level Mac precision in exchange for two first-run gates (Gatekeeper + Location Services TCC), documented in the new TCC solutions doc.
- **HTTPS `ipinfo.io/json` for the IP geo source** over HTTP `ip-api.com`. The doc-review pass surfaced an HTTP-forgery vector when script output goes through tmux's `#()` substitution; HTTPS at the wire layer + sanitization in the worker + 64-byte length cap = three-layer defense.
- **One cross-platform script with `uname` branching** instead of two scripts. Honored throughout; the platform branch is minimal.
- **`--format` (double dash) for CoreLocationCLI**. Swift ArgumentParser silently ignores `-format` (single dash) and emits the default `%latitude %longitude`. Verified: `--format '%locality|%administrativeArea|%isoCountryCode|%country'` returns `El Dorado Hills|CA|US|United States`.
- **Probe-then-fallback for `stat`** (NOT `uname`-based dispatch). On this user's Mac, Homebrew `coreutils` is installed and `/opt/homebrew/bin` precedes `/usr/bin` in PATH, so `stat` resolves to GNU even on Darwin. `stat -f %m` becomes "filesystem status" (multi-line prose) instead of mtime — a maintainability reviewer's "perf" suggestion that would have silently broken on the user's primary host.
- **Drop `|| return 0` from `read -r` in pipeline helpers**. The producer (`printf '%s'`) emits no trailing newline; `read` returns 1 reporting EOF-without-newline but `$s` holds the partial content. The `||` clause was treating a format signal as an error signal.
- **Sanitize on both write AND read** in `location.sh`. Belt-and-suspenders: even if the cache file is somehow tampered with (or written by an older buggy script version), bad bytes never reach the tmux format engine.
- **24-char display truncation in the script itself**, not relying solely on `status-right-length`. Prevents long city names from eating the time/date suffix via tmux's right-side truncation.
- **`/ce-compound` as one combined doc** rather than two narrow docs. The two pitfalls share a meta-pattern (silent late-stage failure hidden by early-stage short-circuit) and surfaced in the same review pass — narrative-driven single doc is tighter for this case.

## What Didn't Work

These were resolved during the session — listed so the next session doesn't relitigate:

- **`brew "corelocationcli"`** — formula-vs-cask error. `corelocationcli` is a Homebrew **cask**, lives at the bottom of `brew/Brewfile` alongside `docker-desktop` and `git-credential-manager`. Plan caught this at doc-review time before any code shipped.
- **Lowercase `corelocationcli` as the binary name** — the cask is named lowercase but the *binary symlink* is `CoreLocationCLI` (capitalized). All script invocations and the recovery doc had to be updated.
- **`%countryCode` token** — does not exist in CoreLocationCLI's flag list; the correct token is `%isoCountryCode`. Plan-time finding.
- **`-format` (single dash)** for CoreLocationCLI — silently ignored by Swift ArgumentParser, falls back to default lat/long. Discovered during code-review verification when the cask was finally installed and exercised. Use `--format` (double dash) or `-f`.
- **`IFS= read -r s || return 0`** in `cap_length` and `display_truncate` — short-circuited on EOF-without-newline, leaving the cache permanently unpopulated. The P0 that almost shipped silently. Behavioral testing missed it because `resolve_darwin` returned 1 (CoreLocationCLI not yet installed at test time) before reaching the broken pipeline.
- **`uname` case statement for `stat -c %Y` vs `stat -f %m`** — a maintainability reviewer's "perf" suggestion. Broke on this user's Mac because GNU `coreutils` is on PATH ahead of `/usr/bin`; reverted to probe-then-fallback.
- **HTTP `ip-api.com`** as the IP-geo default — flagged at doc-review for forgery vector. Switched to HTTPS `ipinfo.io` + small inline ISO-3166 map.
- **One-pass auto-resolve of code-review findings without re-verifying** — caught the doubled-separator concern as a false positive on review, but the `read || return 0` and `-format` bugs only surfaced when the worker pipeline actually ran end-to-end (after installing the cask and granting TCC). Behavioral testing on a host that lacked the optional dependency was the gap.

## What's Next

1. **Nothing queued.** Board is clean — no open PRs, no Forge inbox at session start, no pending tickets. The location-pill is shipped, documented, deployed to VPS, verified rendering on both hosts.

Optional future work (tracked in the plan's `Deferred to Follow-Up Work`, not active):

- Migrate the macOS Gatekeeper + TCC permission setup into the install pipeline (currently manual on first run, documented in the new solutions doc).
- Add `corelocationcli` to the work Mac when ready. Same plan applies; left out of scope for this PR.

## Gotchas & Watch-outs

- **`claude/CLAUDE.md` and `claude/commands/pickup.md` show as `M`** in the working tree. Same as the prior session — externally edited (probably plugin/harness driven). Leave alone, do not commit. They've survived the merge + the post-merge `docs(solutions)` commit; they'll travel forward unchanged.
- **CoreLocationCLI is a cask, binary is `CoreLocationCLI` (capitalized)**. The cask name (`corelocationcli`) is lowercase per Homebrew convention; the binary the cask installs is capitalized. Use the right one in the right place: `brew install corelocationcli`, `brew uninstall --cask corelocationcli`, but `command -v CoreLocationCLI`, `CoreLocationCLI --format ...`.
- **`--format` not `-format`** for CoreLocationCLI. Single-dash silently emits the default `%latitude %longitude` and the script's parsing then fails downstream.
- **`stat` on Mac with Homebrew coreutils:** probe-then-fallback (`stat -c %Y` first, `stat -f %m` second). NEVER `uname`-case dispatch. The user's setup has GNU stat on PATH ahead of BSD `/usr/bin/stat`.
- **`tmux display-message -p '#{T:status-right}'` does NOT actually fire `#()` substitutions.** That quirk burned ~10 minutes during code-review verification — `display-message` returns the raw format string with color directives but does not invoke shell commands inside `#()`. The actual rendered status bar IS invoking the script every status-interval; trust the trace evidence (`pgrep`-style markers, manually-instrumented log appends), not the `display-message` echo.
- **The location pill's worker spawn must include `</dev/null`** for stdin detachment (per `docs/solutions/code-quality/claude-code-hook-stdio-detach.md`). Easy to drop on a future refactor.
- **Cache is local-only** at `${XDG_CACHE_HOME:-$HOME/.cache}/tmux-location/value`. Never commit to the repo. Both Macs and the VPS each have their own.
- **VPS 24h TTL** means a transient ipinfo.io failure → stale Helsinki display for up to 24h. Acceptable per design; if it ever bites, the manual recovery is `ssh root@openclaw-prod '~/.config/tmux/scripts/location.sh --refresh'`.
- **Recovery from a stuck refresh** (script's header comment): `pkill -f tmux-location-refresh-marker`. The 60s lock-TTL self-heal is the automatic recovery; pkill is the manual escape.
- **Carry-forward (still valid):** `##` hex-escape rule for tmux ternaries; `find -exec ... +` over `\;`; ssh-as-root + `>>` first-write ownership trap → trailing `chown` invariant; HANDOFF.md stays on master only — never commit mid-branch; `renumber-windows on` shifts everything when you `kill-window`.

## Compound learning captured this session

- **`docs/solutions/best-practices/bash-pipeline-traps-hidden-by-early-stage-short-circuits-2026-05-01.md`** (`fc0c64a`). Both shell-scripting pitfalls + the meta-lesson about behavioral testing missing late-stage breakage. If a future session hits "the script ran clean but produces no output" or "`stat` is returning weird multi-line text," start here.
