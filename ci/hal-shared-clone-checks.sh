#!/usr/bin/env bash
#
# hal-shared-clone-checks.sh — exercise the VIL-700 part 2 scripts on temp folders:
# helpers/hal_shared_clone_sync.sh (Mac side), helpers/hal_shared_clone.sh (on-hal steps) and
# helpers/hal_dotfiles_sync_check.sh (Atlas's hourly check). Run by hand after changing any of
# them; macOS only (BSD tools, /bin/chmod +a, /usr/bin/git); not in CI.
#
#   ci/hal-shared-clone-checks.sh   prints each case's output; exit 0 when every case behaves
#
# Nothing here reaches hal or this Mac's own dotfiles. A bare repo stands in for GitHub; temp
# folders stand in for `david`'s and `hal`'s homes, each with a clone of it. The Mac-side
# script gets a fake ssh (HAL_SHARED_SSH) that runs the command under zsh in the home its
# alias names (hal: david's, hal-as-hal: hal's; FAKE_SSH_DOWN=<alias> fails that one;
# FAKE_SSH_SAME=1 sends hal-as-hal to david's home too). On that side, fake `id -un` answers
# david or hal by alias (FAKE_SSH_WRONG_USER=<alias>: nobody), and fake `ioreg` gives another
# hardware UUID for FAKE_SSH_OTHER_HOST=<alias>. The
# on-hal steps run as this account, told who to be by HAL_SHARED_TEST_USER; the acl step names
# the real `nobody` account, because chmod +a needs one that exists. Every script runs under
# macOS's /bin/bash 3.2, as hal may run it.
# Cases are eval'd strings, so shellcheck sees their variables as unused.
# shellcheck disable=SC2016,SC2034
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SYNC="$REPO/helpers/hal_shared_clone_sync.sh"
STEPS="$REPO/helpers/hal_shared_clone.sh"
CHECK_SRC="$REPO/helpers/hal_dotfiles_sync_check.sh"
REL=Projects/Personal/dotfiles

T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
T="$(cd "$T" && pwd -P)"
trap 'chflags -R nouchg,nouappnd "$T" 2>/dev/null; chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = master\n' > "$GIT_CONFIG_GLOBAL"

pass=0; fail=0; OUT="$T/out"; RC=0
run() { "$@" > "$OUT" 2>&1; RC=$?; }
show() { sed -e "s|$T|<tmp>|g" "$OUT" | sed 's/^/    /'; }
check() {
  echo "== $1 (exit $RC)"; show
  if eval "$2"; then pass=$((pass+1)); echo "   ok"; else fail=$((fail+1)); echo "   FAIL: $2"; fi
}
has() { grep -qF -- "$1" "$OUT"; }
quiet() { [ ! -s "$OUT" ]; }

# --- fixtures -----------------------------------------------------------------------------
STUB="$T/stub"; mkdir -p "$STUB"
printf '%s\n' '#!/bin/sh' \
  '# Fake ssh: drop options, map the alias to a home, run the command there under zsh.' \
  'while [ $# -gt 0 ]; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done' \
  'host=$1; shift' \
  'case $host in hal) h=$FAKE_DAVID_HOME ;; hal-as-hal) h=$FAKE_HAL_HOME; [ -z "${FAKE_SSH_SAME:-}" ] || h=$FAKE_DAVID_HOME ;; *) echo "fake ssh: unexpected host $host" >&2; exit 255 ;; esac' \
  '[ "${FAKE_SSH_DOWN:-}" = "$host" ] && { echo "ssh: connect to host $host: Operation timed out" >&2; exit 255; }' \
  'cd "$h" || exit 255' \
  'case $host in hal) FAKE_ID=david ;; *) FAKE_ID=hal ;; esac; [ "${FAKE_SSH_WRONG_USER:-}" != "$host" ] || FAKE_ID=nobody' \
  'FAKE_UUID=; [ "${FAKE_SSH_OTHER_HOST:-}" != "$host" ] || FAKE_UUID=00000000-0000-0000-0000-000000000000' \
  "PATH=$STUB/remote:/bin:\$PATH; export PATH FAKE_ID FAKE_UUID" \
  'HOME=$h exec /bin/zsh -f -c "$*"' > "$STUB/ssh"
mkdir -p "$STUB/remote"
printf '%s\n' '#!/bin/sh' '[ "$1" = -un ] && { echo "$FAKE_ID"; exit 0; }; exec /usr/bin/id "$@"' > "$STUB/remote/id"
printf '%s\n' '#!/bin/sh' '[ -n "$FAKE_UUID" ] && { echo "  \"IOPlatformUUID\" = \"$FAKE_UUID\""; exit 0; }; exec /usr/sbin/ioreg "$@"' > "$STUB/remote/ioreg"
chmod 755 "$STUB/ssh" "$STUB/remote/id" "$STUB/remote/ioreg"
export HAL_SHARED_SSH="$STUB/ssh"

ORIGIN="$T/origin.git"; SEED="$T/seed"
DH="$T/david"; HH="$T/hal"
NEW="$DH/$REL"; OLD="$HH/$REL"
export FAKE_DAVID_HOME="$DH" FAKE_HAL_HOME="$HH" HAL_SHARED_REMOTE="file://$ORIGIN"

# The repo paths hal's links point at (herdr/config.toml is missing on purpose: that link is
# dead on hal), plus the scripts under test.
LINKS=$(sed -n "/^LINKS='/,/'\$/p" "$STEPS" | sed "s/^LINKS='//; s/'\$//")
mk_origin() {
  rm -rf "$ORIGIN" "$SEED"; git init -q --bare "$ORIGIN"; git init -q "$SEED"
  local l r
  while read -r l r; do
    [ "$r" = herdr/config.toml ] && continue
    mkdir -p "$SEED/$(dirname "$r")"; echo "content of $r" > "$SEED/$r"
  done <<< "$LINKS"
  mkdir -p "$SEED/helpers" "$SEED/claude" "$SEED/zsh/functions"
  echo "shared CLAUDE.md" > "$SEED/claude/CLAUDE.md"
  # verify runs the clone's zsh/functions.sh with the glob options from its zshrc: the real
  # loader, the real zshrc's setopt lines, and one function.
  awk '/^setopt [A-Z_]*GLOB/ && $2 ~ /^[A-Z_]+$/ { print "setopt " $2 }' "$REPO/zsh/zshrc" > "$SEED/zsh/zshrc"
  grep -qx 'setopt NO_CASE_GLOB' "$SEED/zsh/zshrc" || { echo "zsh/zshrc no longer sets NO_CASE_GLOB; V7 needs it" >&2; exit 1; }
  cp "$REPO/zsh/functions.sh" "$SEED/zsh/"
  echo "f() { :; }" > "$SEED/zsh/functions/f.sh"
  cp "$CHECK_SRC" "$STEPS" "$SEED/helpers/"
  git -C "$SEED" add -A && git -C "$SEED" commit -qm c1 && git -C "$SEED" push -q "$ORIGIN" master
}
# push_commit <file> <subject>: a new commit on the stand-in GitHub's master.
push_commit() { echo "$2" >> "$SEED/$1"; git -C "$SEED" add -- "$1" && git -C "$SEED" commit -qm "$2" && git -C "$SEED" push -q "$ORIGIN" master; }
mk_homes() {
  chmod -R u+rwx "$DH" "$HH" 2>/dev/null; rm -rf "$DH" "$HH"
  mkdir -p "$DH/Projects/Personal" "$HH/Projects/Personal" "$HH/.claude" "$HH/.hermes/scripts"
  chmod 755 "$DH/Projects" "$DH/Projects/Personal"
  # The four paths the acl step closes, at the modes they had on hal (2026-11-16).
  mkdir -p "$DH/.claude/file-history" "$DH/.claude/shell-snapshots" "$DH/scratch"
  chmod 755 "$DH/.claude/file-history" "$DH/.claude/shell-snapshots" "$DH/scratch"
  echo "X=1" > "$DH/env.sh"; chmod 644 "$DH/env.sh"
  git clone -q "file://$ORIGIN" "$NEW"; git clone -q "file://$ORIGIN" "$OLD"
  local l r
  while read -r l r; do mkdir -p "$HH/$(dirname "$l")"; ln -s "$OLD/$r" "$HH/$l"; done <<< "$LINKS"
  echo "hal's own CLAUDE.md" > "$HH/.claude/CLAUDE.md"
  printf '#!/usr/bin/env bash\n# the original sync-check\necho old\n' > "$HH/.hermes/scripts/dotfiles-sync-check.sh"
  chmod 755 "$HH/.hermes/scripts/dotfiles-sync-check.sh"
}
OLDSHA() { shasum -a 256 < "$HH/.hermes/scripts/dotfiles-sync-check.sh" | cut -d' ' -f1; }
# as_hal / as_david <step>: run an on-hal step as that account would, under /bin/bash 3.2.
as_hal() { HOME="$HH" HERMES_HOME="$HH/.hermes" HAL_SHARED_TEST_USER=hal HAL_SHARED_TEST_DAVID_HOME="$DH" \
  HAL_SHARED_TEST_OLD_CHECK_SHA="$OSHA" /bin/bash "$STEPS" "$@"; }
as_david() { HOME="$DH" HAL_SHARED_TEST_USER=david HAL_SHARED_TEST_HAL_USER=nobody HAL_SHARED_TEST_DAVID_HOME="$DH" \
  /bin/bash "$STEPS" "$@"; }
# links_snapshot: every expected link and its target, plus CLAUDE.md's kind.
links_snapshot() {
  local l r
  while read -r l r; do printf '%s %s\n' "$l" "$(readlink "$HH/$l")"; done <<< "$LINKS"
  if [ -L "$HH/.claude/CLAUDE.md" ]; then readlink "$HH/.claude/CLAUDE.md"; else cat "$HH/.claude/CLAUDE.md"; fi
}
all_into() { links_snapshot | awk -v p="$1/" 'NR <= 24 && index($2, p) != 1 { bad = 1 } END { exit bad }'; }
md() { /usr/bin/stat -f %Lp "$DH/$1"; }
modes4() { echo "$(md .claude/file-history) $(md .claude/shell-snapshots) $(md scratch) $(md env.sh)"; }
MODES="$DH/.vil-700-modes-before-acl"
acl_of() { /bin/ls -led "$1" | awk '$2 ~ /^user:/ { $1 = ""; sub(/^ /, ""); print }'; }

# --- Mac side: hal_shared_clone_sync.sh -----------------------------------------------------
mk_origin; mk_homes; OSHA=$(OLDSHA); push_commit README c2
C2=$(git -C "$SEED" rev-parse HEAD); C1=$(git -C "$SEED" rev-parse HEAD~1)
headof() { git -C "$1" rev-parse HEAD; }

DOTFILES_DRY_RUN=1 run /bin/bash "$SYNC"
check "S1 dry run" '[ $RC = 0 ] && [ "$(headof "$NEW")" = "$C1" ] && [ "$(headof "$OLD")" = "$C1" ] && has "not on ${C2:0:7}" && has "Nothing changed"'

run /bin/bash "$SYNC"
check "S2 both clones fast-forwarded" '[ $RC = 0 ] && [ "$(headof "$NEW")" = "$C2" ] && [ "$(headof "$OLD")" = "$C2" ] && has "both clones are on ${C2:0:7}"'

run /bin/bash "$SYNC"
check "S3 second run changes nothing" '[ $RC = 0 ] && [ "$(headof "$NEW")" = "$C2" ] && has "already on"'

push_commit README c3; C3=$(git -C "$SEED" rev-parse HEAD)
printf 'not an index' > "$OLD/.git/index"
run /bin/bash "$SYNC"
check "S10 git status fails in hal's clone: refused, neither moved" '[ $RC = 1 ] && [ "$(headof "$NEW")" = "$C2" ] && [ "$(headof "$OLD")" = "$C2" ] && has "git status failed"'
rm -f "$OLD/.git/index"; git -C "$OLD" reset -q
echo edit >> "$OLD/README"
run /bin/bash "$SYNC"
check "S4 hal's clone has edits: refused, neither moved" '[ $RC = 1 ] && [ "$(headof "$NEW")" = "$C2" ] && [ "$(headof "$OLD")" = "$C2" ] && has "edits to tracked files" && has "Stopped before changing anything"'
git -C "$OLD" checkout -q -- README

git -C "$NEW" checkout -q -b side
run /bin/bash "$SYNC"
check "S5 david's clone on a branch: refused" '[ $RC = 1 ] && [ "$(headof "$OLD")" = "$C2" ] && has "not on master"'
git -C "$NEW" checkout -q master

FAKE_SSH_DOWN=hal-as-hal run /bin/bash "$SYNC"
check "S6 ssh to hal-as-hal fails: nothing changed" '[ $RC = 1 ] && [ "$(headof "$NEW")" = "$C2" ] && has "check over ssh hal-as-hal failed"'

git -C "$OLD" remote set-url origin https://example.invalid/other.git
run /bin/bash "$SYNC"
check "S7 hal's origin isn't GitHub's URL: refused" '[ $RC = 1 ] && [ "$(headof "$NEW")" = "$C2" ] && has "origin of"'
git -C "$OLD" remote set-url origin "file://${ORIGIN%.git}"
run /bin/bash "$SYNC"
check "S7b origin without .git counts as the same URL" '[ $RC = 0 ] && [ "$(headof "$OLD")" = "$C3" ]'
git -C "$OLD" remote set-url origin "file://$ORIGIN"
FAKE_SSH_WRONG_USER=hal-as-hal run /bin/bash "$SYNC"
check "S14 ssh hal-as-hal reaches another account: refused" '[ $RC = 1 ] && has "reached account nobody, not hal" && has "Stopped before changing anything"'
FAKE_SSH_OTHER_HOST=hal-as-hal run /bin/bash "$SYNC"
check "S15 the aliases reach different machines: refused" '[ $RC = 1 ] && has "reach different machines"'
echo edit >> "$OLD/README"; git -C "$OLD" update-index --assume-unchanged README
run /bin/bash "$SYNC"
check "S13 hal's clone has an edit git status can't see (assume-unchanged): refused" '[ $RC = 1 ] && has "flagged assume-unchanged or skip-worktree"'
git -C "$OLD" update-index --no-assume-unchanged README; git -C "$OLD" checkout -q -- README
echo edit >> "$NEW/zsh/zshrc"; git -C "$NEW" update-index --skip-worktree zsh/zshrc
run /bin/bash "$SYNC"
check "S13b david's clone has an edit under skip-worktree: refused" '[ $RC = 1 ] && has "flagged assume-unchanged or skip-worktree"'
git -C "$NEW" update-index --no-skip-worktree zsh/zshrc; git -C "$NEW" checkout -q -- zsh/zshrc
git -C "$OLD" config core.fileMode false; chmod +x "$OLD/README"
run /bin/bash "$SYNC"
check "S13c hal's clone has an executable bit changed under core.fileMode=false: refused" '[ $RC = 1 ] && has "edits to tracked files"'
chmod -x "$OLD/README"; git -C "$OLD" config --unset core.fileMode

echo local >> "$OLD/README"; git -C "$OLD" commit -qam local
run /bin/bash "$SYNC"
check "S8 hal's clone is ahead of master: exit 1, says where each is" '[ $RC = 1 ] && [ "$(headof "$NEW")" = "$C3" ] && has "(local commits?)" && has "aren'"'"'t both on"'
push_commit README c4; C4=$(git -C "$SEED" rev-parse HEAD)
run /bin/bash "$SYNC"
check "S9 hal's clone has diverged: exit 1" '[ $RC = 1 ] && [ "$(headof "$NEW")" = "$C4" ] && has "fast-forward to ${C4:0:7} failed" && has "aren'"'"'t both on"'
git -C "$OLD" reset -q --hard "$C4"
FAKE_SSH_SAME=1 run /bin/bash "$SYNC"
check "S12 both aliases reach the same clone: refused" '[ $RC = 1 ] && has "reach the same clone" && has "Stopped before changing anything"'
# A submodule whose recorded commit moves: the fast-forward leaves its folder behind, which
# isn't an edit to tracked files.
git init -q "$T/sub"; echo s > "$T/sub/s"; git -C "$T/sub" add s; git -C "$T/sub" commit -qm s1
git -C "$SEED" -c protocol.file.allow=always submodule -q add "$T/sub" sub; git -C "$SEED" commit -qm sub1; git -C "$SEED" push -q "$ORIGIN" master
for c in "$NEW" "$OLD"; do git -C "$c" pull -q --ff-only; git -C "$c" -c protocol.file.allow=always submodule -q update --init; done
echo s2 >> "$T/sub/s"; git -C "$T/sub" commit -qam s2; git -C "$SEED/sub" pull -q; git -C "$SEED" commit -qam sub2; git -C "$SEED" push -q "$ORIGIN" master
C5=$(git -C "$SEED" rev-parse HEAD)
run /bin/bash "$SYNC"
check "S11 master moves a submodule: both fast-forwarded, exit 0" '[ $RC = 0 ] && [ "$(headof "$NEW")" = "$C5" ] && [ "$(headof "$OLD")" = "$C5" ] && has "both clones are on ${C5:0:7}"'
run /bin/bash "$SYNC"
check "S11b and again" '[ $RC = 0 ] && has "both clones are on ${C5:0:7}"'

# --- on-hal steps: acl and acl-rollback, as david ----------------------------------------------
mk_origin; mk_homes; OSHA=$(OLDSHA)

run as_hal acl
check "A0 acl as the wrong account" '[ $RC = 1 ] && has "run this step as \`david\`"'
run as_david acl-rollback
check "AR5 acl-rollback before any acl run: done already" '[ $RC = 0 ] && has "done already" && [ "$(modes4)" = "755 755 755 644" ]'
mkdir -m 750 "$DH/grp"
DOTFILES_DRY_RUN=1 run as_david acl
check "A1 acl dry run" '[ $RC = 0 ] && [ -z "$(acl_of "$DH")" ] && [ "$(modes4)" = "755 755 755 644" ] && [ ! -e "$MODES" ] && has "will close ~/scratch: 755 -> 700" && has "will close ~/env.sh: 644 -> 600" && has "will run: /bin/chmod +a \"user:nobody allow search\"" && has "by group and other mode bits alone" && has "~/Projects" && has "~/grp" && ! has "    ~/scratch"'
rmdir "$DH/grp"
chmod 600 "$DH/env.sh"; /bin/chmod +a "user:nobody allow read" "$DH/env.sh"
run as_david acl
check "A10 a path at its closed mode but with an ACL entry allowing access: refused, nothing changed" '[ $RC = 1 ] && has "has an ACL entry that allows access" && [ -z "$(acl_of "$DH")" ] && [ "$(modes4)" = "755 755 755 600" ] && [ "$(acl_of "$DH/env.sh")" = "user:nobody allow read" ] && [ ! -e "$MODES" ]'
/bin/chmod -a "user:nobody allow read" "$DH/env.sh"; chmod 644 "$DH/env.sh"
run as_david acl
check "A2 acl closes the four paths, records their modes, sets the entry" '[ $RC = 0 ] && [ "$(acl_of "$DH")" = "user:nobody allow search" ] && [ "$(modes4)" = "700 700 700 600" ] && [ "$(wc -l < "$MODES" | tr -d " ")" = 4 ] && grep -qx "env.sh 644" "$MODES" && [ "$(/usr/bin/stat -f %Lp "$MODES")" = 600 ] && has "~/env.sh: closed to 600"'
run as_david acl
check "A3 acl again" '[ $RC = 0 ] && has "done already" && [ "$(acl_of "$DH" | wc -l | tr -d " ")" = 1 ] && [ "$(wc -l < "$MODES" | tr -d " ")" = 4 ]'
/bin/chmod +a "user:nobody allow read" "$DH/scratch"
run as_david acl
check "A11 the entry is set, then a path gains an ACL entry: not done already, refused, says the entry stays" '[ $RC = 1 ] && ! has "done already" && has "has an ACL entry that allows access" && has "from an earlier run"'
/bin/chmod -a "user:nobody allow read" "$DH/scratch"
chmod 755 "$DH/scratch"
run as_david acl
check "A3b a path reopened since: closed again, its first mode kept" '[ $RC = 0 ] && ! has "done already" && [ "$(md scratch)" = 700 ] && [ "$(grep -c "^scratch " "$MODES")" = 1 ] && grep -qx "scratch 755" "$MODES"'
chmod 755 "$DH/scratch"; chflags uchg "$DH/scratch"
run as_david acl
check "A12 the entry is set, a reopened path can't be closed: exit 1, says the entry is still there" '[ $RC = 1 ] && has "still has \"user:nobody allow search\" from an earlier run" && ! has "was not set" && ! has "wasn'"'"'t added" && [ "$(acl_of "$DH")" = "user:nobody allow search" ]'
chflags nouchg "$DH/scratch"; run as_david acl
chmod 000 "$MODES"
run as_david acl-rollback
check "AR8 the modes record can't be read: refused, entry kept" '[ $RC = 1 ] && has "can'"'"'t read" && [ -n "$(acl_of "$DH")" ] && [ "$(modes4)" = "700 700 700 600" ]'
chmod 600 "$MODES"; chmod 600 "$DH/.claude"
run as_david acl-rollback
check "AR9 a path's mode can't be read: refused, entry kept" '[ $RC = 1 ] && has "can'"'"'t read the mode of ~/.claude/file-history" && [ -n "$(acl_of "$DH")" ]'
chmod 755 "$DH/.claude"
DOTFILES_DRY_RUN=1 run as_david acl-rollback
check "AR0 acl-rollback dry run" '[ $RC = 0 ] && [ "$(modes4)" = "700 700 700 600" ] && [ -n "$(acl_of "$DH")" ] && has "will reopen ~/env.sh: 600 -> 644"'
run as_david acl-rollback
check "AR1 acl-rollback after the full step" '[ $RC = 0 ] && [ -z "$(acl_of "$DH")" ] && [ "$(modes4)" = "755 755 755 644" ]'
run as_david acl-rollback
check "AR2 acl-rollback again" '[ $RC = 0 ] && has "done already"'
run as_david acl; mv "$MODES" "$T/modes.saved"
run as_david acl-rollback
check "AR7 acl-rollback with the record gone: entry removed, says nothing is put back, paths stay closed" '[ $RC = 0 ] && has "no recorded mode to put back" && [ -z "$(acl_of "$DH")" ] && [ "$(modes4)" = "700 700 700 600" ]'
mv "$T/modes.saved" "$MODES"; run as_david acl-rollback
chflags uchg "$DH/env.sh"
run as_david acl
check "A7 a path can't be closed: exit 1, entry not set, the others closed and said so" '[ $RC = 1 ] && [ -z "$(acl_of "$DH")" ] && has "The entry wasn'"'"'t added" && has "~/scratch: closed to 700" && [ "$(modes4)" = "700 700 700 644" ]'
chflags nouchg "$DH/env.sh"
run as_david acl-rollback
check "AR3 acl-rollback after a step that stopped partway" '[ $RC = 0 ] && [ -z "$(acl_of "$DH")" ] && [ "$(modes4)" = "755 755 755 644" ]'
run as_david acl; /bin/chmod -a "user:nobody allow search" "$DH"; chflags uchg "$DH/.claude/file-history"
run as_david acl-rollback
check "AR6 acl-rollback, no entry, the first path can't be reopened: exit 1 naming it, the rest reopened" '[ $RC = 1 ] && has "didn'"'"'t go back to their recorded mode: ~/.claude/file-history" && [ "$(modes4)" = "700 755 755 644" ]'
chflags nouchg "$DH/.claude/file-history"; run as_david acl-rollback
mv "$DH/scratch" "$T/scratch.saved"
run as_david acl
check "A8 a path doesn't exist: skipped, the rest closed, entry set" '[ $RC = 0 ] && has "~/scratch doesn'"'"'t exist; skipped" && [ "$(md env.sh)" = 600 ] && [ -n "$(acl_of "$DH")" ]'
run as_david acl-rollback
mv "$T/scratch.saved" "$DH/scratch"
check "AR4 acl-rollback with that path back" '[ $RC = 0 ] && [ -z "$(acl_of "$DH")" ] && [ "$(md env.sh)" = 644 ]'
mv "$DH/env.sh" "$T/env.saved"; ln -s "$T/env.saved" "$DH/env.sh"
run as_david acl
check "A9 a path is a link: refused, nothing closed" '[ $RC = 1 ] && [ -z "$(acl_of "$DH")" ] && [ "$(md scratch)" = 755 ] && has "is a link"'
rm "$DH/env.sh"; mv "$T/env.saved" "$DH/env.sh"
/bin/chmod +a "user:nobody allow list" "$DH"
run as_david acl
check "A4 another entry for the account: refused" '[ $RC = 1 ] && [ "$(acl_of "$DH")" = "user:nobody allow list" ] && has "already has another entry"'
/bin/chmod -a "user:nobody allow list" "$DH"
chmod 700 "$DH/Projects"
run as_david acl
check "A5 clone's folders closed to others: refused" '[ $RC = 1 ] && [ -z "$(acl_of "$DH")" ] && has "isn'"'"'t searchable by group and other"'
chmod 755 "$DH/Projects"; chmod 600 "$NEW/zsh/zshrc"
run as_david acl
check "A6 a file in the clone closed to others: refused" '[ $RC = 1 ] && has "zsh/zshrc"'
chmod 644 "$NEW/zsh/zshrc"

# --- on-hal steps as hal -------------------------------------------------------------------------
CK="$HH/.hermes/scripts/dotfiles-sync-check.sh"
run as_hal sync-check-rollback
check "C00 sync-check-rollback before any install: done already" '[ $RC = 0 ] && has "done already" && grep -q "echo old" "$CK"'
chmod 000 "$DH"
run as_hal relink
check "R00 relink while the clone is closed: stops at that" '[ $RC = 1 ] && all_into "$OLD" && [ "$(grep -c "^  !" "$OUT")" = 1 ]'
run as_hal sync-check
check "C0 sync-check while the clone is closed: refused" '[ $RC = 1 ] && has "run the acl step as david first" && grep -q "echo old" "$CK"'
chmod 755 "$DH"
run as_hal relink
check "R0 relink before sync-check: refused" '[ $RC = 1 ] && all_into "$OLD" && has "run the sync-check step first"'
DOTFILES_DRY_RUN=1 run as_hal sync-check
check "C1 sync-check dry run" '[ $RC = 0 ] && grep -q "echo old" "$CK" && [ ! -e "$CK.pre-vil700" ] && has "[dry-run]"'
cp "$CK" "$T/ck.saved"; echo "# edited by Atlas" >> "$CK"
run as_hal sync-check
check "C2 the installed check isn't the expected original: refused" '[ $RC = 1 ] && has "sha256 differs" && [ ! -e "$CK.pre-vil700" ]'
cp "$T/ck.saved" "$CK"
chflags uappnd "$HH/.hermes/scripts"
run as_hal sync-check
check "C12 install fails and its temp copy can't be removed: exit 1, named, original kept" '[ $RC = 1 ] && has "remove it by hand" && has "kept the original" && grep -q "echo old" "$CK"'
chflags nouappnd "$HH/.hermes/scripts"; rm -f "$CK".vil700-tmp.*
run as_hal sync-check
check "C3 sync-check (after C12 stopped partway)" '[ $RC = 0 ] && cmp -s "$CHECK_SRC" "$CK" && grep -q "echo old" "$CK.pre-vil700" && [ "$(/usr/bin/stat -f %Lp "$CK")" = 755 ]'
run as_hal sync-check
check "C4 sync-check again" '[ $RC = 0 ] && has "done already"'
mv "$CK.pre-vil700" "$T/keep.saved"
run as_hal sync-check
check "C8 installed but the original isn't kept: refused" '[ $RC = 1 ] && ! has "done already"'
cp "$T/keep.saved" "$CK.pre-vil700"; echo "# edited" >> "$CK.pre-vil700"
run as_hal sync-check
check "C8b installed, kept copy isn't the original: refused" '[ $RC = 1 ] && has "isn'"'"'t the original check" && ! has "done already"'
mv "$T/keep.saved" "$CK.pre-vil700"
mv "$HH/.config/zsh/.zshrc" "$T/zshrc.link"
run as_hal sync-check-rollback
check "C9 sync-check-rollback with no zshrc link: refused" '[ $RC = 1 ] && cmp -s "$CHECK_SRC" "$CK" && has "doesn'"'"'t point into"'
mv "$T/zshrc.link" "$HH/.config/zsh/.zshrc"
mv "$CK" "$T/ck.real"; ln -s "$CHECK_SRC" "$CK"
run as_hal sync-check
check "C10 the installed check is a link to the source: refused" '[ $RC = 1 ] && ! has "done already"'
rm "$CK"; mv "$T/ck.real" "$CK"
echo "# an older copy" >> "$CK"
run as_hal relink
check "R8 relink with an older copy of the check: refused" '[ $RC = 1 ] && all_into "$OLD" && has "isn'"'"'t step 3'"'"'s"'
run as_hal sync-check
check "C14 an older copy of this repo's check: replaced" '[ $RC = 0 ] && cmp -s "$CHECK_SRC" "$CK"'

echo x > "$NEW/x"; git -C "$NEW" add x; git -C "$NEW" commit -qm x
run as_hal relink
check "R2 clones on different commits: refused" '[ $RC = 1 ] && all_into "$OLD" && has "aren'"'"'t on one commit"'
git -C "$NEW" reset -q --hard HEAD~1
mv "$NEW/btop/btop.conf" "$T/btop.saved"
run as_hal relink
check "R1 a linked file is missing in the shared clone: refused" '[ $RC = 1 ] && all_into "$OLD" && has "btop/btop.conf is missing or unreadable"'
mv "$T/btop.saved" "$NEW/btop/btop.conf"
before=$(links_snapshot)
DOTFILES_DRY_RUN=1 run as_hal relink
check "R3 relink dry run" '[ $RC = 0 ] && [ "$(links_snapshot)" = "$before" ] && has "will move 24 link(s)"'
chmod 555 "$HH"
run as_hal relink
check "R3b relink fails at the first link: exit 1, nothing moved" '[ $RC = 1 ] && all_into "$OLD" && has "after moving 0 link(s)"'
chmod 755 "$HH"
chflags uappnd "$HH"
run as_hal relink
check "R3c first link fails and its temp link can't be removed: exit 1, named" '[ $RC = 1 ] && has "remove it by hand" && all_into "$OLD"'
chflags nouappnd "$HH"; rm -f "$HH"/.gitconfig.vil700-tmp.*
chmod 555 "$HH/.config/tmux/scripts"
run as_hal relink
check "R4 relink fails partway: exit 1, says how many moved" '[ $RC = 1 ] && has "after moving 11 link(s) on this run" && has "Run relink again to finish"'
chmod 755 "$HH/.config/tmux/scripts"
echo pulled >> "$NEW/zsh/zshrc"; git -C "$NEW" commit -qam pulled
run as_hal relink-rollback
check "B0 relink-rollback from a partial relink, after a pull" '[ $RC = 0 ] && all_into "$OLD" && [ ! -L "$HH/.claude/CLAUDE.md" ]'
git -C "$NEW" reset -q --hard HEAD~1
run as_hal relink
check "R5 relink" '[ $RC = 0 ] && all_into "$NEW" && [ "$(readlink "$HH/.claude/CLAUDE.md")" = "$NEW/claude/CLAUDE.md" ] && grep -q "own CLAUDE.md" "$HH/.claude/CLAUDE.md.pre-vil700"'
run as_hal relink
check "R6 relink again" '[ $RC = 0 ] && has "done already"'
run as_hal verify
check "V1 verify" '[ $RC = 0 ] && has "ok:"'
mkdir "$HH/.closed"; chmod 000 "$HH/.closed"
run as_hal verify
check "V3 part of the home can't be scanned: verify fails" '[ $RC = 1 ] && has "couldn'"'"'t scan all of"'
chmod 755 "$HH/.closed"; rmdir "$HH/.closed"
mv "$NEW/btop/btop.conf" "$T/btop.saved"
run as_hal verify
check "V4 a linked file is missing from the clone: verify fails" '[ $RC = 1 ] && has "btop/btop.conf is missing"'
mv "$T/btop.saved" "$NEW/btop/btop.conf"
# david's home searchable but not readable, as on hal: the old loader's absolute glob fails
# under NO_CASE_GLOB, and verify must say so; the repo's loader works.
printf '%s\n' 'for function in "$DOTFILES/zsh/functions"/*.sh; do . "${function}"; done' > "$NEW/zsh/functions.sh"
chmod 311 "$DH"
run as_hal verify
check "V7 david's home search-only, a loader that globs through it: verify fails" '[ $RC = 1 ] && has "defined no function from"'
git -C "$NEW" checkout -q -- zsh/functions.sh
run as_hal verify
check "V8 the same home with the repo's loader: verify passes" '[ $RC = 0 ] && has "function loader works"'
chmod 755 "$DH"
printf '# no glob options here\n' > "$NEW/zsh/zshrc"
run as_hal verify
check "V9 zshrc has no setopt ...GLOB line: verify fails, not a probe without the options" '[ $RC = 1 ] && has "couldn'"'"'t read the glob options"'
printf '%s\n' 'setopt NO_CASE_GLOB && touch "$HOME/vil700-ran"' 'setopt EXTENDED_GLOB' > "$NEW/zsh/zshrc"
run as_hal verify
check "V10 a glob line with an appended command: only the option is used, the command doesn't run" '[ $RC = 0 ] && [ ! -e "$HH/vil700-ran" ]'
printf '%s\n' 'setopt NO_CASE_GLOB*' 'setopt EXTENDED_GLOB' > "$NEW/zsh/zshrc"
mkdir -p "$T/cwd"; touch "$T/cwd/NO_CASE_GLOB"
in_cwd() { (cd "$T/cwd" && as_hal "$@"); }
run in_cwd verify
check "V11 a glob character in the option token, a matching file in the working folder: verify fails" '[ $RC = 1 ] && has "couldn'"'"'t read the glob options"'
git -C "$NEW" checkout -q -- zsh/zshrc
printf '%s\n' 'print -r -- "$DOTFILES/zsh/functions/f.sh"' > "$NEW/zsh/functions/f.sh"
run as_hal verify
check "V12 a function file prints a path under zsh/functions but defines nothing: verify fails" '[ $RC = 1 ] && has "defined no function from"'
git -C "$NEW" checkout -q -- zsh/functions/f.sh
chmod 000 "$NEW/claude/CLAUDE.md"
run as_hal verify
check "V6 CLAUDE.md's target is unreadable: verify fails" '[ $RC = 1 ] && has "claude/CLAUDE.md is missing or unreadable"'
chmod 644 "$NEW/claude/CLAUDE.md"
ln -s "$OLD/README" "$HH/.config/stray"
run as_hal verify
check "V2 a stray link into the old clone" '[ $RC = 1 ] && has "links still into"'
run as_hal retire-old-clone
check "T0 retire with a stray link: refused" '[ $RC = 1 ] && [ -d "$OLD/.git" ]'
rm "$HH/.config/stray"

run as_hal sync-check-rollback
check "C5 sync-check-rollback while linked to the shared clone: refused" '[ $RC = 1 ] && cmp -s "$CHECK_SRC" "$CK"'
cp "$CK" "$T/ck.new"; cp "$CK.pre-vil700" "$CK"
run as_hal sync-check-rollback
check "C16 the original check active while linked to the shared clone: refused, not done already" '[ $RC = 1 ] && ! has "done already" && has "doesn'"'"'t point into"'
cp "$T/ck.new" "$CK"
run as_hal relink-rollback
check "B1 relink-rollback" '[ $RC = 0 ] && all_into "$OLD" && [ ! -L "$HH/.claude/CLAUDE.md" ] && grep -q "own CLAUDE.md" "$HH/.claude/CLAUDE.md" && [ ! -e "$HH/.claude/CLAUDE.md.pre-vil700" ]'
run as_hal relink-rollback
check "B2 relink-rollback again" '[ $RC = 0 ] && has "done already"'
chflags uappnd "$HH/.hermes/scripts"
run as_hal sync-check-rollback
check "C13 rollback fails and its temp copy can't be removed: exit 1, named" '[ $RC = 1 ] && has "remove it by hand" && cmp -s "$CHECK_SRC" "$CK"'
chflags nouappnd "$HH/.hermes/scripts"; rm -f "$CK".vil700-tmp.*
run as_hal sync-check-rollback
check "C6 sync-check-rollback" '[ $RC = 0 ] && grep -q "echo old" "$CK" && [ -f "$CK.pre-vil700" ]'
run as_hal sync-check
check "C7 sync-check after its rollback" '[ $RC = 0 ] && cmp -s "$CHECK_SRC" "$CK"'
ln "$HH/.claude/CLAUDE.md" "$HH/.claude/CLAUDE.md.pre-vil700"
run as_hal relink
check "R7 relink after a run that stopped with CLAUDE.md kept but not linked" '[ $RC = 0 ] && all_into "$NEW" && [ "$(readlink "$HH/.claude/CLAUDE.md")" = "$NEW/claude/CLAUDE.md" ]'

DOTFILES_DRY_RUN=1 run as_hal retire-old-clone
check "T1 retire dry run" '[ $RC = 0 ] && [ -d "$OLD/.git" ] && has "will run: /bin/mv"'
run as_hal retire-old-clone
check "T2 retire" '[ $RC = 0 ] && [ ! -e "$OLD" ] && [ -d "$OLD.pre-vil700/.git" ]'
run as_hal retire-old-clone
check "T3 retire again" '[ $RC = 0 ] && has "done already"'
mv "$OLD.pre-vil700" "$T/aside.saved"; mkdir "$OLD.pre-vil700"
run as_hal retire-old-clone
check "T5 no clone at the old path, a non-clone folder aside: refused" '[ $RC = 1 ] && ! has "done already"'
rmdir "$OLD.pre-vil700"; mv "$T/aside.saved" "$OLD.pre-vil700"
run as_hal relink-rollback
check "B3 relink-rollback after retire: refused" '[ $RC = 1 ] && all_into "$NEW" && has "restore-old-clone first"'
run as_hal restore-old-clone
check "T4 restore-old-clone" '[ $RC = 0 ] && [ -d "$OLD/.git" ] && [ ! -e "$OLD.pre-vil700" ]'
run as_hal restore-old-clone
check "T6 restore-old-clone again" '[ $RC = 0 ] && has "done already"'
echo pulled >> "$NEW/zsh/zshrc"; git -C "$NEW" commit -qam pulled
run as_hal relink-rollback
check "B4 relink-rollback after a pull as david" '[ $RC = 0 ] && all_into "$OLD" && grep -q "own CLAUDE.md" "$HH/.claude/CLAUDE.md"'
git -C "$NEW" reset -q --hard HEAD~1
run as_hal relink
rm "$HH/.claude/CLAUDE.md"; mv "$HH/.claude/CLAUDE.md.pre-vil700" "$HH/.claude/CLAUDE.md"; ln "$HH/.claude/CLAUDE.md" "$HH/.claude/CLAUDE.md.pre-vil700"
run as_hal relink-rollback
check "B7 relink-rollback, all links moved but CLAUDE.md only kept, not linked" '[ $RC = 0 ] && all_into "$OLD" && [ ! -L "$HH/.claude/CLAUDE.md" ]'
run as_hal relink
run as_hal retire-old-clone
echo pulled >> "$NEW/zsh/zshrc"; git -C "$NEW" commit -qam pulled
run as_hal restore-old-clone
run as_hal relink-rollback
check "B5 retired, pulled, restored, then relink-rollback" '[ $RC = 0 ] && all_into "$OLD"'
git -C "$NEW" reset -q --hard HEAD~1
run as_hal relink
check "R10 relink again after that" '[ $RC = 0 ] && all_into "$NEW"'
echo pulled >> "$NEW/zsh/zshrc"; git -C "$NEW" commit -qam pulled
run as_hal relink
check "R11 relink after a pull as david: done already" '[ $RC = 0 ] && has "done already"'
git -C "$NEW" reset -q --hard HEAD~1
run as_hal retire-old-clone
echo pulled >> "$NEW/zsh/zshrc"; git -C "$NEW" commit -qam pulled
echo "# changed on master" >> "$NEW/helpers/hal_dotfiles_sync_check.sh"; git -C "$NEW" commit -qam "check changed"
run as_hal retire-old-clone
check "T7 retired, then a pull changed the check: still done already" '[ $RC = 0 ] && has "done already"'
run as_hal verify
check "V5 the same state: verify names the stale check" '[ $RC = 1 ] && has "isn'"'"'t an executable copy"'
run as_hal sync-check
check "C15 the same state: sync-check replaces the stale copy, verify passes" '[ $RC = 0 ] && cmp -s "$NEW/helpers/hal_dotfiles_sync_check.sh" "$CK" && as_hal verify > /dev/null'
run as_hal restore-old-clone
git -C "$NEW" reset -q --hard HEAD~2; cp "$CHECK_SRC" "$CK"

run as_hal nonsense
check "U1 unknown step" '[ $RC = 2 ]'

# --- zsh/functions.sh itself, under zshrc's glob options ------------------------------------
LZ() { zsh -f -c 'setopt NO_CASE_GLOB EXTENDED_GLOB GLOB_DOTS; DOTFILES=$1; reply=("$2"); source "$1/zsh/functions.sh"
  whence -w hh; print -r -- "vars: ${+function} ${+f} ${(j: :)reply}"' zsh "$@"; }
run LZ "$REPO" keep
check "Z1 functions defined inside the loader are global; it leaves no variable and leaves reply alone" 'has "hh: function" && has "vars: 0 0 keep"'
mkdir -p "$T/nofns/zsh/functions"; cp "$REPO/zsh/functions.sh" "$T/nofns/zsh/"; echo 'print STALE-SOURCED' > "$T/stale.sh"
run LZ "$T/nofns" "$T/stale.sh"
check "Z2 no function file: nothing sourced, no error, a stale reply isn't used" '[ $RC = 0 ] && ! has "STALE-SOURCED" && ! has "no matches"'

# --- the sync-check itself, as hal, watching the clone hal's links point into -----------------
# State is now: links into $NEW, both clones on c1, the new check installed.
SC() { HOME="$HH" HERMES_HOME="$HH/.hermes" DOTFILES_SYNC_REMOTE="file://$ORIGIN" DOTFILES_SYNC_MIRROR="${DOTFILES_SYNC_MIRROR:-$T/mirror.git}" \
  DOTFILES_SYNC_STATE="$T/state" /bin/bash "$@"; }
h7() { git -C "$NEW" rev-parse --short=7 HEAD; }
rm -f "$T/state"
run SC "$CK"
check "K1 in sync: silent" '[ $RC = 0 ] && quiet'
run SC "$CK"
check "K2 again: silent" '[ $RC = 0 ] && quiet'
push_commit README "c2 subject"
run SC "$CK"
check "K3 behind: one report" '[ $RC = 0 ] && has "1 commit(s) behind" && has "c2 subject" && has "git -C ~/Projects/Personal/dotfiles pull --ff-only"'
run SC "$CK"
check "K4 same state: silent" '[ $RC = 0 ] && quiet'
echo "evil" >> "$NEW/zsh/zshrc"
run SC "$CK"
check "K22 behind and tampered: the label names the clone's commit, not master" '[ $RC = 0 ] && has "differ from $(h7)* (1): \`zsh/zshrc\`" && ! has "differ from master"'
git -C "$NEW" checkout -q -- zsh/zshrc
git -C "$NEW" pull -q --ff-only
run SC "$CK"
check "K5 pulled: silent" '[ $RC = 0 ] && quiet'
echo "evil" >> "$NEW/zsh/zshrc"
run SC "$CK"
check "K6 tampered file" '[ $RC = 0 ] && has "differ from $(h7)* (1): \`zsh/zshrc\`"'
git -C "$NEW" checkout -q -- zsh/zshrc
echo "evil" > "$NEW/zsh/functions/evil.sh"
run SC "$CK"
check "K7 extra file" '[ $RC = 0 ] && has "not in $(h7)* (1): \`zsh/functions/evil.sh\`"'
rm "$NEW/zsh/functions/evil.sh"
mv "$NEW/git/gitignore" "$T/gi"; ln -s /etc/hosts "$NEW/git/gitignore"
run SC "$CK"
check "K8 file replaced by a link" '[ $RC = 0 ] && has "*is a link* (1): \`git/gitignore\`"'
rm "$NEW/git/gitignore"; mv "$T/gi" "$NEW/git/gitignore"
M7=$(h7)
echo local >> "$NEW/README"; git -C "$NEW" add README; git -C "$NEW" commit -qm local
run SC "$CK"
check "K9 clone on a commit that isn't on master: compared with master" '[ $RC = 0 ] && has "isn'"'"'t on master" && has "differ from $M7* (1): \`README\`"'
git -C "$NEW" reset -q --hard origin/master
run SC "$CK"
check "K10 back in sync: silent" '[ $RC = 0 ] && quiet'
# Failure injection: a copy of the check with fake tools first on its PATH. FAIL_TOOL names a
# tool that fails when one of its arguments contains FAIL_ARG; FAKE_TMP_DIR=<name> has mktemp
# leave a folder of that name in the temp folder, so the check's writes to that file fail.
# Each case hides a difference that the failing command would otherwise have found.
FB="$T/fakebin"; mkdir -p "$FB"
printf '%s\n' '#!/bin/sh' 'n=${0##*/}' \
  'if [ "$n" = "${FAIL_TOOL:-}" ]; then for a in "$@"; do case $a in *"${FAIL_ARG:-}"*) exit 1 ;; esac; done; fi' \
  'if [ "$n" = mktemp ] && [ -n "${FAKE_TMP_DIR:-}" ]; then d=$(/usr/bin/mktemp "$@") || exit 1; mkdir "$d/$FAKE_TMP_DIR"; echo "$d"; exit 0; fi' \
  'exec /usr/bin/$n "$@"' > "$FB/tool"
chmod 755 "$FB/tool"; for t in paste awk sed comm mktemp; do ln -s tool "$FB/$t"; done
sed "s|^PATH=/usr/bin|PATH=$FB:/usr/bin|" "$CK" > "$T/ck-fault.sh"
failed_loud() { [ $RC = 1 ] && tail -n 1 "$OUT" | grep -q "^dotfiles-sync-check: "; }
echo "evil" >> "$NEW/zsh/zshrc"
FAIL_TOOL="paste" run SC "$T/ck-fault.sh"
check "K24 paste fails while a file is tampered: exit 1, not a pass" 'failed_loud'
git -C "$NEW" checkout -q -- zsh/zshrc
echo "evil" > "$NEW/zsh/functions/evil.sh"
FAIL_TOOL="awk" FAIL_ARG="getline" run SC "$T/ck-fault.sh"
check "K25 the awk that drops submodule folders fails while an extra file is there: exit 1" 'failed_loud'
rm "$NEW/zsh/functions/evil.sh"
chmod +x "$NEW/zsh/zshrc"
FAIL_TOOL="sed" FAIL_ARG='s|^' run SC "$T/ck-fault.sh"
check "K26 the sed on the executable list fails while an exec bit changed: exit 1" 'failed_loud'
FAIL_TOOL="comm" FAIL_ARG="-3" run SC "$T/ck-fault.sh"
check "K27 comm -3 fails while an exec bit changed: exit 1" 'failed_loud'
FAKE_TMP_DIR=regular run SC "$T/ck-fault.sh"
check "K28 a temp file can't be written: exit 1, naming that" 'failed_loud && has "couldn'"'"'t write its temp files"'
chmod -x "$NEW/zsh/zshrc"
echo "evil" >> "$NEW/zsh/zshrc"
FAIL_TOOL="awk" FAIL_ARG='$1 == k' run SC "$T/ck-fault.sh"
check "K29 the report's awk fails while a file is tampered: exit 1, not a report without it" 'failed_loud && ! has "differ from"'
git -C "$NEW" checkout -q -- zsh/zshrc
chmod +x "$NEW/zsh/zshrc"
run SC "$CK"
check "K21 executable bit added to a tracked file" '[ $RC = 0 ] && has "executable bit differs from $(h7)* (1): \`zsh/zshrc\`"'
chmod -x "$NEW/zsh/zshrc"
run SC "$CK"
check "K21b back: silent" '[ $RC = 0 ] && quiet'
# A hostile url.insteadOf in the watched clone's gitconfig can't redirect the check's fetch.
git init -q --bare "$T/evil.git"; git -C "$SEED" push -q "$T/evil.git" HEAD~1:refs/heads/master
mkdir -p "$T/evilhome"; printf '[url "file://%s"]\n\tinsteadOf = file://%s\n' "$T/evil.git" "$ORIGIN" > "$T/evilhome/.gitconfig"
env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM HOME="$T/evilhome" DOTFILES_CLONE="$NEW" DOTFILES_SYNC_REMOTE="file://$ORIGIN" DOTFILES_SYNC_MIRROR="$T/mirror.git" \
  DOTFILES_SYNC_STATE="$T/state" /bin/bash "$CK" > "$OUT" 2>&1; RC=$?
check "K11 ~/.gitconfig ignored" '[ $RC = 0 ] && quiet'
cp "$CK" "$T/ck-edited.sh"; echo "# local edit" >> "$T/ck-edited.sh"
run SC "$T/ck-edited.sh"
STEP3=$(grep -o "ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh sync-check'" "$REPO/docs/reference/install-and-server.md" | head -n 1)
check "K12 installed check isn't master's: the report gives the guide's step 3 command" '[ $RC = 0 ] && has "this check isn'"'"'t master'"'"'s" && [ -n "$STEP3" ] && has "\`$STEP3\`"'
HOME="$HH" DOTFILES_SYNC_REMOTE="file://$T/nope.git" DOTFILES_SYNC_MIRROR="$T/mirror.git" DOTFILES_SYNC_STATE="$T/state" run /bin/bash "$CK"
check "K13 GitHub unreachable: exit 1 with a reason" '[ $RC = 1 ] && has "fetch of GitHub'"'"'s master failed"'
chmod 000 "$DH"
run SC "$CK"
check "K14 clone unreadable: exit 1 with a reason" '[ $RC = 1 ] && has "can'"'"'t read"'
chmod 755 "$DH"
chmod 000 "$NEW/zsh/functions"
run SC "$CK"
check "K18 a folder in the clone is unreadable: exit 1" '[ $RC = 1 ] && has "can'"'"'t list"'
chmod 755 "$NEW/zsh/functions"
chmod 444 "$T/state"
run SC "$CK"
check "K19 in sync, state can't be written: exit 1, not silent, only its own reason" '[ $RC = 1 ] && has "couldn'"'"'t write" && ! has "Permission denied"'
push_commit README "c-k20"
run SC "$CK"
check "K20 report, state can't be written: the report, then the reason as the last line, exit 1" '[ $RC = 1 ] && has "c-k20" && tail -n 1 "$OUT" | grep -q "will repeat"'
chmod 644 "$T/state"
st=$(cat "$T/state"); git -C "$NEW" pull -q --ff-only
DOTFILES_DRY_RUN=1 run SC "$CK"
check "K16 dry run with a mirror: reports, writes no state" '[ $RC = 0 ] && has "[dry-run] compared with" && has "in sync" && [ "$(cat "$T/state")" = "$st" ]'
printf 'x\n' > "$SEED/a
b"; git -C "$SEED" add -A && git -C "$SEED" commit -qm newline && git -C "$SEED" push -q "$ORIGIN" master; git -C "$NEW" pull -q --ff-only
run SC "$CK"
check "K23 a tracked path with a newline: reported as an odd path, not a failure" '[ $RC = 0 ] && has "*odd path* (1): \`a?b\`"'
ln -s target "$SEED/lnk"; git -C "$SEED" add lnk && git -C "$SEED" commit -qm lnk && git -C "$SEED" push -q "$ORIGIN" master; git -C "$NEW" pull -q --ff-only
rm "$NEW/lnk"; ln -s $'target\n' "$NEW/lnk"
run SC "$CK"
check "K30 a tracked link's target gains a trailing newline: reported" '[ $RC = 0 ] && grep -q "differ from.*\`lnk\`" "$OUT"'
rm "$NEW/lnk"; ln -s target "$NEW/lnk"
DOTFILES_DRY_RUN=1 DOTFILES_SYNC_MIRROR="$T/no-mirror.git" run SC "$CK"
check "K17 dry run without a mirror: creates nothing" '[ $RC = 0 ] && has "Would create" && [ ! -e "$T/no-mirror.git" ]'

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
