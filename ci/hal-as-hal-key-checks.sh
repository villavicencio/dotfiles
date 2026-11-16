#!/usr/bin/env bash
#
# hal-as-hal-key-checks.sh — exercise helpers/add_hal_as_hal_key.sh on temp folders (VIL-700).
# Run by hand after changing the helper; not in CI.
#
#   ci/hal-as-hal-key-checks.sh   prints each case's output; exit 0 when every case behaves
#
# Nothing here reaches hal: the helper gets a fake ssh (HAL_AS_HAL_SSH) that runs the command
# under zsh, as hal's login shell does, in a temp "remote home" (FAKE_OLD_BASH=1 puts /bin first
# on its PATH, so the hal side runs in macOS's bash 3.2), a fake tailscale (HAL_AS_HAL_TAILSCALE) and a throwaway
# key (HAL_AS_HAL_PUBKEY). FAKE_SSHKEYGEN_FAIL=1 puts an ssh-keygen first on the fake remote's
# PATH that runs the real one FAKE_SSHKEYGEN_OK_CALLS times (default 0), then fails.
# Cases are eval'd strings, so shellcheck sees their variables as unused.
# shellcheck disable=SC2016,SC2034
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO/helpers/add_hal_as_hal_key.sh"

T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub" "$T/badkeygen" "$T/remote/.ssh"

printf '%s\n' '#!/bin/sh' \
  '# Fake ssh: take the host, run the command in $FAKE_REMOTE_HOME as if logged in there.' \
  '[ "$1" = hal-orca ] || { echo "fake ssh: unexpected host $1" >&2; exit 255; }' \
  'shift' \
  'if [ -n "${FAKE_SSHKEYGEN_FAIL:-}" ]; then PATH="$FAKE_BADKEYGEN:$PATH"; export PATH; fi' \
  'cd "$FAKE_REMOTE_HOME" || exit 255' \
  'if [ -n "${FAKE_OLD_BASH:-}" ]; then PATH="/bin:$PATH"; export PATH; fi' \
  'HOME=$FAKE_REMOTE_HOME exec /bin/zsh -f -c "$*"' > "$T/stub/ssh"
printf '%s\n' '#!/bin/sh' 'echo "100.64.0.7"' > "$T/stub/tailscale"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$T/stub/tailscale-none"
printf '%s\n' '#!/bin/sh' \
  'n=$(cat "$FAKE_KG_COUNT" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_KG_COUNT"' \
  '[ "$n" -le "${FAKE_SSHKEYGEN_OK_CALLS:-0}" ] && exec /usr/bin/ssh-keygen "$@"' \
  'echo "ssh-keygen: simulated failure" >&2; exit 1' > "$T/badkeygen/ssh-keygen"
chmod 755 "$T/stub/"* "$T/badkeygen/ssh-keygen"
export FAKE_REMOTE_HOME="$T/remote" FAKE_BADKEYGEN="$T/badkeygen" FAKE_KG_COUNT="$T/kg.count"
export HAL_AS_HAL_SSH="$T/stub/ssh" HAL_AS_HAL_TAILSCALE="$T/stub/tailscale"

ssh-keygen -q -t ed25519 -N '' -C fake-orca -f "$T/orca" || exit 1
ssh-keygen -q -t ed25519 -N '' -C fake-main -f "$T/main" || exit 1
ssh-keygen -q -t rsa -b 2048 -N '' -C fake-rsa -f "$T/rsa" || exit 1
export HAL_AS_HAL_PUBKEY="$T/main.pub"
AK="$T/remote/.ssh/authorized_keys"
BODY=$(awk '{print $2}' "$T/main.pub")
PIN='from="100.64.0.7",no-agent-forwarding,no-X11-forwarding'
ORCA_LINE="$PIN $(cat "$T/orca.pub")"

reset_ak() { rm -f "$AK" "$AK".bak-*; printf '%s\n' "$ORCA_LINE" > "$AK"; chmod 600 "$AK"; }

pass=0; fail=0; OUT="$T/out"; RC=0
run() { "$@" > "$OUT" 2>&1; RC=$?; }
show() { sed -e "s|$BODY|<KEY BODY>|g" -e "s|$T|<tmp>|g" "$OUT" | sed 's/^/    /'; }
check() {
  local name=$1 cond=$2
  echo "== $name (exit $RC)"; show
  if eval "$cond"; then pass=$((pass+1)); echo "   ok"; else fail=$((fail+1)); echo "   FAIL: $cond"; fi
}
lines() { wc -l < "$AK" | tr -d ' '; }
hal_side() { "$T/stub/ssh" hal-orca bash -s -- "$@" < <(sed -n '/^_hal_side() {/,/^}/p' "$HELPER"; echo '_hal_side "$@"'); }
nobody_in_out() { ! grep -qF "$BODY" "$OUT"; }

# 1. clean add
reset_ak; run bash "$HELPER"
check "1 clean add" '[ $RC = 0 ] && [ "$(lines)" = 2 ] && tail -n 1 "$AK" | grep -q "^$PIN ssh-ed25519 $BODY mac-main-key hal-as-hal " && head -n 1 "$AK" | grep -qF "$ORCA_LINE" && ls "$AK".bak-* >/dev/null 2>&1 && nobody_in_out'

# 2. second run: present and correctly pinned
reset_ak; bash "$HELPER" >/dev/null 2>&1; h=$(shasum "$AK"); run bash "$HELPER"
check "2 second run" '[ $RC = 0 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "already present with the intended options" "$OUT"'

# 3. present with a different from=
reset_ak; printf '%s\n' "from=\"100.64.0.99\",no-agent-forwarding,no-X11-forwarding ssh-ed25519 $BODY old" >> "$AK"
h=$(shasum "$AK"); run bash "$HELPER"
check "3 present, other from=" '[ $RC = 3 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "options on hal: from=\"100.64.0.99\"" "$OUT" && grep -qF "intended:       $PIN" "$OUT" && nobody_in_out'

# 4. present with no options
reset_ak; printf '%s\n' "ssh-ed25519 $BODY old" >> "$AK"
h=$(shasum "$AK"); run bash "$HELPER"
check "4 present, no options" '[ $RC = 3 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "options on hal: (none)" "$OUT" && nobody_in_out'

# 5. authorized_keys without a trailing newline
rm -f "$AK" "$AK".bak-*; printf '%s' "$ORCA_LINE" > "$AK"; chmod 600 "$AK"; run bash "$HELPER"
check "5 no trailing newline" '[ $RC = 0 ] && [ "$(lines)" = 2 ] && [ "$(head -n 1 "$AK")" = "$ORCA_LINE" ] && tail -n 1 "$AK" | grep -q "^$PIN ssh-ed25519 $BODY mac-main-key hal-as-hal " && [ "$(ssh-keygen -lf "$AK" | wc -l | tr -d " ")" = 2 ] && nobody_in_out'

# 6. non-ed25519 input
reset_ak; h=$(shasum "$AK"); HAL_AS_HAL_PUBKEY="$T/rsa.pub" run bash "$HELPER"
check "6 non-ed25519 key" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "not an ed25519 public key" "$OUT"'

# 7. bad pin address reaching the hal side. The Mac side refuses it first; this calls the hal
# side directly. The value must be shell-safe: values reach hal as ssh arguments, which is why
# the Mac side checks them before sending.
reset_ak; h=$(shasum "$AK"); run hal_side '10.0.0' ssh-ed25519 "$BODY"
check "7 bad pin address (hal side)" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "unexpected pin address" "$OUT"'
run hal_side 100.64.0.7 ssh-rsa "$BODY"
check "7b non-ed25519 type (hal side)" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "not an ed25519 public key" "$OUT"'
run hal_side 100.64.0.7 ssh-ed25519 'AAAA@@@@'
check "7c bad key data (hal side)" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "unexpected key data" "$OUT"'

# 8. no tailscale address
reset_ak; h=$(shasum "$AK"); HAL_AS_HAL_TAILSCALE="$T/stub/tailscale-none" run bash "$HELPER"
check "8 no tailscale address" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "nothing sent" "$OUT"'

# 9. ssh-keygen failing on hal, before anything is written
reset_ak; rm -f "$FAKE_KG_COUNT"; h=$(shasum "$AK"); FAKE_SSHKEYGEN_FAIL=1 run bash "$HELPER"
check "9 ssh-keygen fails on the new key" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "ssh-keygen can.t read the new key" "$OUT"'
reset_ak; rm -f "$FAKE_KG_COUNT"; h=$(shasum "$AK"); FAKE_SSHKEYGEN_FAIL=1 FAKE_SSHKEYGEN_OK_CALLS=1 run bash "$HELPER"
check "9a ssh-keygen fails reading authorized_keys" '[ $RC = 1 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "ssh-keygen can.t read .*authorized_keys; nothing changed" "$OUT"'

# 9b. ssh-keygen failing when it re-reads the file after the append: exit 4, backup named
reset_ak; rm -f "$FAKE_KG_COUNT"; h=$(shasum < "$AK"); FAKE_SSHKEYGEN_FAIL=1 FAKE_SSHKEYGEN_OK_CALLS=2 run bash "$HELPER"
check "9b ssh-keygen fails after the append" '[ $RC = 4 ] && grep -q "Restore with: cp -p" "$OUT" && [ "$(shasum < "$AK".bak-*)" = "$h" ] && nobody_in_out'

# 10. dry run sends nothing
reset_ak; h=$(shasum "$AK"); DOTFILES_DRY_RUN=1 run bash "$HELPER"
check "10 dry run" '[ $RC = 0 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "^\[dry-run\]" "$OUT"'

# 11. the key twice, both lines correct: already present, nothing appended
reset_ak; printf '%s\n' "$PIN ssh-ed25519 $BODY a" "$PIN ssh-ed25519 $BODY b" >> "$AK"
h=$(shasum "$AK"); run bash "$HELPER"
check "11 two identical correct lines" '[ $RC = 0 ] && [ "$(shasum "$AK")" = "$h" ] && grep -q "already present with the intended options" "$OUT"'

# 12. correct line with tabs between options, type and body: found, nothing appended
reset_ak; printf '%s\t%s\t%s\t%s\n' "$PIN" ssh-ed25519 "$BODY" tabbed >> "$AK"
h=$(shasum "$AK"); run bash "$HELPER"
check "12 tab-separated existing line" '[ $RC = 0 ] && [ "$(shasum "$AK")" = "$h" ]'

# 13. a .pub file without a trailing newline
reset_ak; printf '%s' "$(cat "$T/main.pub")" > "$T/main-nonl.pub"; HAL_AS_HAL_PUBKEY="$T/main-nonl.pub" run bash "$HELPER"
check "13 .pub without trailing newline" '[ $RC = 0 ] && [ "$(lines)" = 2 ]'

# 14. clean add with macOS's /bin/bash 3.2 on the hal side
reset_ak; FAKE_OLD_BASH=1 run bash "$HELPER"
check "14 hal side in /bin/bash 3.2" '[ $RC = 0 ] && [ "$(lines)" = 2 ] && tail -n 1 "$AK" | grep -q "^$PIN ssh-ed25519 $BODY mac-main-key hal-as-hal "'

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
