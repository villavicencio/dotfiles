#!/usr/bin/env bash
# Post-deploy smoke test invoked by .github/workflows/sync-vps.yml
# after `./install` completes on the target host. Prints OK on success;
# exits non-zero on failure (which triggers rollback in the workflow).
#
# Extracted from the workflow for shellcheck-ability and to let a second
# Linux host drop its own ~/.dotfiles-healthcheck.sh for host-specific
# assertions (see bottom of this script).

set -euo pipefail

# 1. Permanent check: at least one openclaw-* container is running.
#    `^openclaw-` prefix match survives Coolify UUID rotation.
running=$(docker ps --format '{{.Names}}' | grep -c '^openclaw-' || true)
if [ "$running" -lt 1 ]; then
  echo "FAIL: no openclaw-* container running"
  exit 1
fi

# 2. Permanent check: interactive zsh inits cleanly.
#    Catches zshrc regressions (bad PATH, syntax error in sourced file).
if ! zsh -i -c exit >/dev/null 2>&1; then
  echo "FAIL: zsh -i -c exit non-zero"
  exit 1
fi

# 3. Transient check: openclaw status --deep reports no CRITICAL/ERROR.
#    Retry up to 3 times with exponential backoff + small jitter — tolerates
#    brief CRITICAL during container restart. Permanent failures (container
#    vanished) still fail fast because we'd have exited in check #1.
CID=$(docker ps --filter name=openclaw- -q | head -1)
if [ -z "$CID" ]; then
  echo "FAIL: docker ps filter returned no container ID"
  exit 1
fi

attempt=1
max_attempts=3
while : ; do
  bad=$(docker exec "$CID" openclaw status --deep 2>&1 | grep -cE '^(CRITICAL|ERROR)' || true)
  if [ "$bad" = "0" ]; then
    break
  fi
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "FAIL: openclaw status dirty after ${max_attempts} attempts (${bad} bad lines in last check)"
    exit 1
  fi
  # sleep ~ 2^attempt + jitter[0,2], capped at 10s.
  delay=$(( (1 << attempt) + (RANDOM % 3) ))
  if [ "$delay" -gt 10 ]; then
    delay=10
  fi
  sleep "$delay"
  attempt=$((attempt + 1))
done

# 4. Optional host-specific hook. If ~/.dotfiles-healthcheck.sh exists and
#    is executable, run it for host-specific assertions. Missing hook is
#    fine — the generic checks above are the baseline.
if [ -x "$HOME/.dotfiles-healthcheck.sh" ]; then
  if ! "$HOME/.dotfiles-healthcheck.sh"; then
    echo "FAIL: host-specific healthcheck (~/.dotfiles-healthcheck.sh) exited non-zero"
    exit 1
  fi
fi

echo "OK: all post-deploy checks passed"
