#!/usr/bin/env bash
#
# add_hal_as_hal_key.sh — put this Mac's main public key (~/.ssh/id_ed25519.pub) on the `hal`
# account's ~/.ssh/authorized_keys on hal, pinned to this Mac's tailnet IPv4 address with the
# same options as the hal-orca key (VIL-700). Setup step 1 of "Reaching hal as `hal`" in
# docs/reference/install-and-server.md.
#
# Personal Mac only, run by hand, once: ./install doesn't call it. David runs it; an agent
# session doesn't. It logs in as `hal` over `ssh hal-orca`, because until this key is in,
# that is the only login as `hal` without a password.
#
#   bash helpers/add_hal_as_hal_key.sh
#
# What it does:
#   - Sends only the key's type and base64 body, and the pin address from `tailscale ip -4`.
#     Never the private key. Both ends check that they are an ed25519 key and a dotted-quad
#     IPv4 address (digit groups only; the octets' range isn't checked).
#   - If the key is already on hal (matched as "<type> <body>", any spaces or tabs between):
#     exit 0 when every line with it has exactly the intended options; otherwise print that line's options and the intended ones, change nothing, exit 3.
#     It never rewrites or removes an existing line; that is David's call.
#   - Otherwise: make a new backup of authorized_keys (only on a run that is about to append;
#     it never overwrites an older backup, and a copy that doesn't match is removed), make
#     sure the file ends in a newline, append one line
#     (comment `mac-main-key hal-as-hal <date>`), then check that the new line is the last
#     line, that ssh-keygen reads one more key than before, and that one of them is the new
#     key. It prints the options it wrote and the fingerprints now on hal.
#
# Exit: 0 added, already correct, or DOTFILES_DRY_RUN=1 (nothing sent); 1 refused or a check
# failed before authorized_keys was changed; 3 key present with other options, nothing
# changed; 4 the write or a check after it failed (restore from the backup it names). Any
# other code: ssh or the shell on hal failed, and the exit code doesn't tell the state of the
# file; look at it (the setup doc has the command). Running this again is safe: it adds the
# key only when it's missing and refuses a line with other options.
#
# Overrides, for ci/hal-as-hal-key-checks.sh only: HAL_AS_HAL_SSH, HAL_AS_HAL_TAILSCALE,
# HAL_AS_HAL_PUBKEY, and HAL_AS_HAL_TEST_BACKUP_TIME (the backup name's timestamp).
set -uo pipefail

SSH="${HAL_AS_HAL_SSH:-ssh}"
TAILSCALE="${HAL_AS_HAL_TAILSCALE:-tailscale}"
PUBKEY="${HAL_AS_HAL_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"
OPTS_TAIL="no-agent-forwarding,no-X11-forwarding"

# Runs on hal as `hal`, sent over ssh as a function. Args: pin address, key type, key body.
_hal_side() {
  set -u
  local a=$1 t=$2 k=$3 f=$HOME/.ssh/authorized_keys
  local want="from=\"$a\",no-agent-forwarding,no-X11-forwarding"
  [[ $a =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "unexpected pin address; nothing changed" >&2; return 1; }
  [ "$t" = ssh-ed25519 ] || { echo "not an ed25519 public key; nothing changed" >&2; return 1; }
  [[ $k =~ ^[A-Za-z0-9+/]+=*$ ]] || { echo "unexpected key data; nothing changed" >&2; return 1; }
  [ -f "$f" ] || { echo "$f is missing; nothing changed" >&2; return 1; }

  # Lines that already carry this key, as their options (the text before "<type> <body>").
  # Runs of spaces and tabs count as one space, and the body must end at a space or the end
  # of the line. Identical lines collapse to one.
  local existing
  existing=$(awk -v tk="$t $k" '{ l = $0; gsub(/[ \t]+/, " ", l); i = index(l " ", tk " "); if (i) { o = substr(l, 1, i - 1); sub(/ $/, "", o); print (o == "" ? "(none)" : o) } }' "$f" | sort -u)
  if [ -n "$existing" ]; then
    if [ "$existing" = "$want" ]; then
      echo "key already present with the intended options ($want); nothing changed"
      return 0
    fi
    echo "key already present, but not with the intended options; nothing changed" >&2
    printf '  options on hal: %s\n' "$existing" >&2
    printf '  intended:       %s\n' "$want" >&2
    echo "  Changing or removing that line is David's decision; this script won't." >&2
    return 3
  fi

  local fp before after bak line
  # The hal-orca line is always there, so ssh-keygen finds at least one key in the file.
  fp=$(printf '%s %s\n' "$t" "$k" | ssh-keygen -lf - | awk '{print $2}') && [ -n "$fp" ] ||
    { echo "ssh-keygen can't read the new key; nothing changed" >&2; return 1; }
  before=$(ssh-keygen -lf "$f") || { echo "ssh-keygen can't read $f; nothing changed" >&2; return 1; }
  # A new backup file on every run that is about to append. The name is claimed empty with
  # noclobber (O_EXCL), so an older backup is never overwritten; a taken name moves on to the
  # next suffix. Then the copy is filled and compared. A copy that fails or doesn't match is
  # removed, so no incomplete backup is left or named. HAL_AS_HAL_TEST_BACKUP_TIME fixes the
  # timestamp for ci/hal-as-hal-key-checks.sh only; ssh doesn't pass it to hal.
  local base n=0
  umask 077
  base="$f.bak-${HAL_AS_HAL_TEST_BACKUP_TIME:-$(/bin/date +%Y%m%d-%H%M%S)}"
  bak=$base
  until ( set -o noclobber; : > "$bak" ) 2>/dev/null; do
    n=$((n + 1))
    if [ "$n" -gt 20 ] || ! { [ -e "$bak" ] || [ -L "$bak" ]; }; then
      echo "can't create a new backup next to $f; nothing changed" >&2; return 1
    fi
    bak="$base.$n"
  done
  if ! { cat "$f" > "$bak" && cmp -s "$f" "$bak" && touch -r "$f" "$bak"; }; then
    rm -f "$bak"
    echo "couldn't make a backup that matches $f; nothing changed" >&2; return 1
  fi
  line="$want $t $k mac-main-key hal-as-hal $(/bin/date +%F)"
  # $(tail -c 1) is empty when the file ends in a newline (or is empty).
  if [ -n "$(tail -c 1 "$f")" ]; then printf '\n' >> "$f" || { echo "write failed; restore with: cp -p $bak $f" >&2; return 4; }; fi
  if ! { printf '%s\n' "$line" >> "$f" && /bin/chmod 600 "$f"; }; then
    echo "write failed; restore with: cp -p $bak $f" >&2; return 4
  fi

  local bad=''
  [ "$(tail -n 1 "$f")" = "$line" ] || bad="the new entry isn't the last line"
  if [ -z "$bad" ]; then
    after=$(ssh-keygen -lf "$f") || bad="ssh-keygen can't read the file after the append"
  fi
  if [ -z "$bad" ] && [ "$(printf '%s\n' "$after" | wc -l)" -ne $(( $(printf '%s\n' "$before" | wc -l) + 1 )) ]; then
    bad="ssh-keygen doesn't read exactly one more key than before"
  fi
  if [ -z "$bad" ] && ! printf '%s\n' "$after" | awk -v fp="$fp" '$2 == fp && /mac-main-key hal-as-hal/ { found = 1 } END { exit !found }'; then
    bad="the new key isn't among the keys ssh-keygen reads"
  fi
  if [ -n "$bad" ]; then
    echo "appended, but $bad. Restore with: cp -p $bak $f" >&2
    return 4
  fi
  echo "added; options written: $(tail -n 1 "$f" | awk -v tk="$t $k" '{ print substr($0, 1, index($0, tk) - 2) }')"
  echo "backup: $bak"
  echo "keys now on hal:"
  printf '%s\n' "$after" | cut -d' ' -f2-
}

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would add $PUBKEY to hal's authorized_keys over ssh hal-orca, pinned to this Mac's tailnet IPv4"
  exit 0
fi

a=$("$TAILSCALE" ip -4 2>/dev/null | head -n 1)
[[ $a =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] ||
  { echo "no tailnet IPv4 from 'tailscale ip -4' (CLI missing or not connected); nothing sent" >&2; exit 1; }
t='' k=''
if ! [ -r "$PUBKEY" ] || ! { read -r t k _ || [ -n "$k" ]; } < "$PUBKEY"; then
  echo "can't read $PUBKEY; nothing sent" >&2; exit 1
fi
[ "$t" = ssh-ed25519 ] || { echo "$PUBKEY is not an ed25519 public key; nothing sent" >&2; exit 1; }
[[ $k =~ ^[A-Za-z0-9+/]+=*$ ]] || { echo "$PUBKEY has unexpected key data; nothing sent" >&2; exit 1; }

echo "pinning to $a with options from=\"$a\",$OPTS_TAIL"
# The function travels on stdin; the three checked values are its arguments.
"$SSH" hal-orca bash -s -- "$a" "$t" "$k" < <(declare -f _hal_side; echo '_hal_side "$@"')
