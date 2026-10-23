#!/usr/bin/env bash
#
# op-agent-checks.sh — exercise bin/op-agent's guards against a stub `op` (no 1Password
# account or network). Run by hand after changing bin/op-agent; not in CI.
#
#   ci/op-agent-checks.sh        exit 0 when every case behaves
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# The stub echoes its args and whether it got the token. For `run`, it runs whatever follows
# `--`, as op does, so the test sees the child's environment. Every call is also counted in
# $T/calls, so a refused case can show op was never reached.
printf '%s\n' '#!/usr/bin/env bash' \
  "echo called >> '$T/calls'" \
  'if [ "$1" = run ]; then printf "%s token=%s\n" "$*" "${#OP_SERVICE_ACCOUNT_TOKEN}" > "$OP_STUB_LOG"' \
  '  while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done; shift; exec "$@"; fi' \
  'echo "op $* token=${#OP_SERVICE_ACCOUNT_TOKEN}"' > "$T/bin/op"
chmod +x "$T/bin/op"
printf 'ops_fake_token\n' > "$T/token"; chmod 600 "$T/token"
ln -s /dev/stdout "$T/stdout-link"
fail=0
run() { : > "$T/run.log"; : > "$T/calls"; PATH="$T/bin:$PATH" OP_AGENT_TOKEN_FILE="$T/token" OP_STUB_LOG="$T/run.log" "$REPO/bin/op-agent" "$@" 2>&1; }
expect() {  # expect <ok|refused> <args...>
  local want="$1"; shift; local out rc pass=0
  out="$(run "$@")"; rc=$?
  # A refusal must come from op-agent itself: a non-zero exit with op never called.
  if [ "$want" = refused ]; then [ "$rc" != 0 ] && [ ! -s "$T/calls" ] && pass=1
  elif [ "$rc" = 0 ]; then
    # An allowed call must reach op with exactly its arguments and the token. `run` hands off
    # to the child, so the stub logs what op got: the original arguments, with
    # `env -u OP_SERVICE_ACCOUNT_TOKEN --` inserted right after the first `--`.
    if [ "$1" = run ]; then
      local pre=() post=() seen=0 a
      for a in "$@"; do
        if [ "$seen" = 0 ]; then pre+=("$a"); [ "$a" = -- ] && seen=1; else post+=("$a"); fi
      done
      [ "$(cat "$T/run.log")" = "${pre[*]} env -u OP_SERVICE_ACCOUNT_TOKEN -- ${post[*]} token=14" ] && pass=1
    elif [ "$out" = "op $* token=14" ]; then pass=1; fi
  fi
  if [ "$pass" = 1 ]; then
    printf 'ok      %-8s %s\n' "$want" "$*"
  else
    printf 'FAIL    want %-8s rc=%s %s\n        %s\n' "$want" "$rc" "$*" "$out"; fail=1
  fi
}
expect ok      whoami
expect ok      item list
expect ok      vault list
expect ok      service-account ratelimit
expect ok      read -o "$T/out" op://Agents/x/y
expect ok      read --out-file="$T/out" op://Agents/x/y
expect ok      inject -i a.tpl -o "$T/a.env"
expect ok      run --env-file .env -- true
expect refused read op://Agents/x/y
expect refused read -o - op://Agents/x/y
expect refused read -o /dev/stdout op://Agents/x/y
expect refused read -o/dev/fd/1 op://Agents/x/y
expect refused read -o=/dev/stdout op://Agents/x/y
expect refused read -o=- op://Agents/x/y
expect ok      read -o="$T/out" op://Agents/x/y
expect refused read --out-file=/proc/self/fd/1 op://Agents/x/y
expect refused read -o "$T/stdout-link" op://Agents/x/y
expect refused read -o
expect refused inject -i a.tpl
expect refused run --no-masking -- true
expect refused run --no-masking=true -- true
expect ok      run -- echo --no-masking   # after --, it's the child's argument
expect refused run true
expect refused run --
expect refused run -- --
expect refused run -- -i
expect refused run -- FOO=bar
expect refused run -- FOO=bar sh -c true
expect refused run --env-file .env --
expect refused item get foo
expect refused item get foo --reveal=true
expect refused signin
expect refused account add
# The child of `run` must not see the token.
child="$(run run -- sh -c 'printf %s "${OP_SERVICE_ACCOUNT_TOKEN-unset}"')"
if [ "$child" = unset ]; then echo "ok      run's child has no OP_SERVICE_ACCOUNT_TOKEN"
else echo "FAIL    run's child saw the token: $child"; fail=1; fi
# Token file rules: mode, link, empty.
chmod 644 "$T/token"; expect refused whoami; chmod 600 "$T/token"
ln -s "$T/token" "$T/tlink"; : > "$T/calls"
if PATH="$T/bin:$PATH" OP_AGENT_TOKEN_FILE="$T/tlink" "$REPO/bin/op-agent" whoami >/dev/null 2>&1 \
  || [ -s "$T/calls" ]; then
  echo "FAIL    a linked token file was accepted"; fail=1; else echo "ok      refused  linked token file"; fi
: > "$T/token"; expect refused whoami
exit "$fail"
