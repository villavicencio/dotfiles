---
module: dotfiles
date: 2026-05-01
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - "Writing bash helper functions that consume stdin via `IFS= read -r` and guard with `|| return 0`"
  - "Refactoring shell scripts to deduplicate `stat`/`date` calls via `uname`-based dispatch"
  - "Operating on macOS with Homebrew `coreutils` installed and `/opt/homebrew/bin` ahead of `/usr/bin` in PATH (the standard dotfiles convention)"
  - "Reviewing a behavioral test pass when the script depends on optional binaries (e.g. `CoreLocationCLI`) that may not be present on the test machine"
  - "Diagnosing a feature that ships green from manual testing but produces empty output / `unbound variable` errors in production"
tags:
  - bash
  - shell-scripting
  - read-builtin
  - stat
  - coreutils
  - gnu-vs-bsd
  - homebrew
  - pipeline
  - silent-failure
  - testing-methodology
related_components:
  - development_workflow
  - tooling
---

# Bash pipeline traps that hide behind early-stage short-circuits

## Context

Shell scripts composed as pipelines — where each stage filters, transforms, or gates output for the next — create a structural blind spot for behavioral testing. When an early stage short-circuits (returns empty, exits early, or otherwise swallows input before passing it downstream), the broken late stages are never exercised. Tests pass, the feature appears to work, and the defects lie dormant until the pipeline runs end-to-end under real conditions.

This pattern surfaced during development of `tmux/scripts/location.sh` for the status-bar location pill (PR #55, merged 2026-05-01). Two distinct bugs lived in late-stage pipeline helpers. Both were invisible during behavioral testing because `CoreLocationCLI` was not yet installed on the test machine — the script exited via `|| exit 0` at the Darwin resolver stage, before any data reached `cap_length`, `display_truncate`, or the stat block. **Static code review surfaced both defects that runtime testing missed entirely.**

The two bugs that almost shipped silently broken are documented below as concrete instances of the same root failure mode.

## Guidance

### Trap A — `IFS= read -r s || return 0` short-circuits on EOF-without-newline

`read -r` returns exit code **1** when it hits EOF without seeing a trailing newline — *even if it successfully read a full string into `s`*. This is not an error; it is standard POSIX behavior reporting the input format. When you guard `read` with `|| return 0`, you silently discard the string and return from the function producing no output. Any caller checking for empty output then short-circuits, and the pipeline dies without a log line, an error, or any visible signal.

**Buggy pattern:**

```bash
cap_length() {
  local s
  IFS= read -r s || return 0       # ← WRONG: short-circuits when producer omits trailing newline
  [ ${#s} -le 64 ] && printf '%s' "$s"
}
```

Caller:

```bash
cleaned=$(printf '%s' "$raw" | sanitize | cap_length)
[ -z "$cleaned" ] && exit 0        # cleaned is empty → script exits silently
```

`printf '%s' "$raw"` emits no trailing newline. `read -r` reads `$s` with the full content but returns 1. `|| return 0` short-circuits — the function returns without printing. The caller sees an empty `$cleaned` and exits. Cache file never written, pill stays empty, entire feature broken — no error, no log, no signal.

**Fixed pattern:**

```bash
cap_length() {
  local s
  IFS= read -r s                   # ignore exit code — EOF-without-newline is normal here
  [ ${#s} -le 64 ] && printf '%s' "$s"
}
```

The rule: **`read`'s exit code communicates input format (was there a newline?), not input validity.** Callers that use `printf '%s'` without a trailing newline — which is correct practice for pipeline intermediates — will always trigger the newline-absent exit code. Do not act on it.

### Trap B — `uname`-based BSD-stat dispatch breaks when GNU `coreutils` precedes system tools in PATH

A common refactor instinct: replace a probe-then-fallback pattern with a `uname` case statement that looks cleaner and equally portable. **The refactor is not equivalent** when Homebrew `coreutils` is installed and `/opt/homebrew/bin` precedes `/usr/bin` in PATH — the standard configuration in this dotfiles repo. On that setup, `stat` resolves to GNU stat even on Darwin, making the `Darwin)` branch hand the BSD flag `-f %m` to a GNU binary. GNU stat interprets `-f` as "filesystem status" and emits multi-line prose:

```
File: "/path/to/cache"
  ID: 100000f0000001a Namelen: ?       Type: apfs
Block size: 4096       Fundamental block size: 4096
...
```

That prose string gets stored in `$mtime`. Downstream arithmetic like `$((now - mtime))` triggers bash to parse the word `File` as a variable name. With `set -u` active, this errors as `File: unbound variable` — the first runtime signal of the bug.

**Suggested refactor (silently broken on Homebrew-coreutils machines):**

```bash
case "$(uname)" in
  Darwin) mtime=$(stat -f %m "$cache_file" 2>/dev/null || printf '0') ;;
  *)      mtime=$(stat -c %Y "$cache_file" 2>/dev/null || printf '0') ;;
esac
```

**Correct pattern — probe then fallback:**

```bash
if   mtime=$(stat -c %Y "$cache_file" 2>/dev/null) && [ -n "$mtime" ]; then :   # GNU stat
elif mtime=$(stat -f %m "$cache_file" 2>/dev/null) && [ -n "$mtime" ]; then :   # BSD stat
else mtime=0
fi
```

Probe-then-fallback works regardless of which `stat` binary PATH resolves to, requires no OS detection, and is the same number of lines as the case statement. Prefer it wherever `stat`, `date`, or other tools have divergent GNU/BSD flags. The same logic applies to `date -d` (GNU) vs `date -j` (BSD), `find -printf` (GNU only), `sed -i` extension argument (BSD requires explicit `''`), and similar tool-shape differences.

## Why This Matters

Both bugs share the same root failure mode: **the broken code was never reached during behavioral testing, so no test could catch it.** The tmux location pill appeared to work end-to-end — the cache file simply was never written when `CoreLocationCLI` was absent, which looks identical to the pill being legitimately empty. There was no error, no log line, no visible delta in behavior. The only path to discovery was reading the code statically and reasoning about what happens when real location data flows through.

This failure mode is especially dangerous in shell scripts because:

- **Exit codes are overloaded.** `read`'s "no newline at EOF" return-1 is informational; treating it as an error silently discards valid data. Same shape applies to many builtins — `wait`'s "no children" return-1, `grep`'s "no matches" return-1, etc.
- **Silent empty-string propagation is indistinguishable from "nothing to show".** Pipeline helpers that emit nothing on failure look identical to ones that emit nothing on legitimate empty input.
- **`set -e` and `|| exit/return` patterns interact with POSIX exit-code semantics in non-obvious ways.** The same idiom can be correct in one stage and silently broken in another, depending on what the producer pipes in.
- **Behavioral tests on machines missing optional dependencies never exercise the full pipeline.** A test that runs the script and confirms "no error" tells you nothing about late stages that the early stages never reached.

The Trap B refactor adds a second dimension: a change that is *visually equivalent* and passes review on the primary developer machine fails silently on any machine where Homebrew coreutils is installed first in PATH. The "cleanup" suggestion was internally consistent and well-intentioned — it just assumed an environment that the dotfiles repo's own conventions actively configure away from.

## When to Apply

**The `read || return` rule applies when:**

- A shell function reads from stdin using `read -r` to process pipeline input
- The producer uses `printf '%s'` or any mechanism that emits no trailing newline
- The function is guarded with `|| return 0` (or `|| return 1`, or `|| exit 0`) immediately after `read`
- The function is a filter or transformer (cap_length, truncate, sanitize, validate, etc.)

In all of those cases, drop the `||` clause. `$s` holds the partial content; trust it. If you need to gate on emptiness, check `[ -n "$s" ]` *after* the read, not the read's exit code.

**The probe-then-fallback rule applies when:**

- Calling `stat`, `date`, `find`, `xargs`, `sed -i`, or similar tools with divergent GNU/BSD flags
- The target machines include macOS with Homebrew `coreutils` (PATH convention in this repo puts `/opt/homebrew/bin` first — see [`brew-shellenv-clobbers-path-via-path-helper.md`](../code-quality/brew-shellenv-clobbers-path-via-path-helper.md))
- You are tempted to replace a probe-then-fallback with a `uname` case statement for cleanliness
- A code review suggests deduplication that changes the selection strategy from runtime probe to static OS detection — push back, the probe is doing real work

**The meta-principle — exercise pipeline stages in isolation — applies when:**

- Any stage of a pipeline can short-circuit early based on system state (tool not installed, env var absent, file not found)
- The script is being developed on a machine that differs from production in any optional dependency
- Behavioral tests confirm "it works" but the actual late-stage code paths have never produced output during a test run

## Examples

### Reproducing the `read || return` trap

```bash
# Reproduce the bug:
f() { local s; IFS= read -r s || return 0; printf '%s' "$s"; }
result=$(printf 'hello' | f)   # producer: no trailing newline
echo "result: '$result'"       # → result: ''   ← silent discard

# With the fix:
f() { local s; IFS= read -r s; printf '%s' "$s"; }
result=$(printf 'hello' | f)
echo "result: '$result'"       # → result: 'hello'   ← correct
```

### Confirming which `stat` is on PATH

```bash
# On a Homebrew-coreutils machine:
which stat                     # /opt/homebrew/bin/stat   (GNU)
stat --version | head -1       # stat (GNU coreutils) 9.x

# The BSD flag silently returns wrong data:
stat -f %m /etc/hosts          # multi-line "File: …" prose, not a timestamp

# The probe pattern handles either:
if   mtime=$(stat -c %Y /etc/hosts 2>/dev/null) && [ -n "$mtime" ]; then echo "GNU: $mtime"
elif mtime=$(stat -f %m /etc/hosts 2>/dev/null) && [ -n "$mtime" ]; then echo "BSD: $mtime"
fi
```

### Exercising pipeline stages in isolation

```bash
# Instead of only running the script end-to-end:
bash tmux/scripts/location.sh

# Also exercise each stage with synthetic input that mimics the producer:
printf 'a very long string that exceeds the cap' | bash -c '. tmux/scripts/location.sh; cap_length'
printf 'short' | bash -c '. tmux/scripts/location.sh; display_truncate'

# And specifically verify the no-newline case (the one that bit us):
printf 'no newline here' | cap_length   # must NOT produce empty string
```

## Related

- [`docs/solutions/code-quality/brew-shellenv-clobbers-path-via-path-helper.md`](../code-quality/brew-shellenv-clobbers-path-via-path-helper.md) — upstream cause: how `/opt/homebrew/bin` gets ahead of `/usr/bin` in PATH, which is what enables the GNU-stat shadow that breaks Trap B.
- [`docs/solutions/cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md`](../cross-machine/ssh-as-root-write-ownership-and-exit-propagation.md) — parallel pattern in a different shell context: a later pipeline stage masks the exit code of an earlier one (`&&`-chained `mv` failures swallowed by a downstream `chown`). Same abstract failure mode (a late stage hides what an earlier stage actually did) in a different idiom.
- [`docs/solutions/code-quality/python-fstring-brace-collapse-breaks-format-strings-2026-04-29.md`](../code-quality/python-fstring-brace-collapse-breaks-format-strings-2026-04-29.md) — same pattern family in Python: a language-level escape rule silently corrupts output that *looks* structurally valid; behavioral tests pass because the surrounding string is intact.
- The location-pill plan that preceded this learning: `docs/plans/2026-05-01-001-feat-tmux-location-pill-plan.md`. The plan's doc-review pass caught major issues at plan time; this learning captures the two that survived to code-review time.
