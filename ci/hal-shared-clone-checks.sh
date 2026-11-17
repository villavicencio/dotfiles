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
# alias names (hal: david's, hal-as-hal: hal's; FAKE_SSH_DOWN=<alias> fails that one). The
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
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
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
  'case $host in hal) h=$FAKE_DAVID_HOME ;; hal-as-hal) h=$FAKE_HAL_HOME ;; *) echo "fake ssh: unexpected host $host" >&2; exit 255 ;; esac' \
  '[ "${FAKE_SSH_DOWN:-}" = "$host" ] && { echo "ssh: connect to host $host: Operation timed out" >&2; exit 255; }' \
  'cd "$h" || exit 255' \
  'PATH=/bin:$PATH; export PATH' \
  'HOME=$h exec /bin/zsh -f -c "$*"' > "$STUB/ssh"
chmod 755 "$STUB/ssh"
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
  echo "a function" > "$SEED/zsh/functions/f.sh"
  cp "$CHECK_SRC" "$STEPS" "$SEED/helpers/"
  git -C "$SEED" add -A && git -C "$SEED" commit -qm c1 && git -C "$SEED" push -q "$ORIGIN" master
}
# push_commit <file> <subject>: a new commit on the stand-in GitHub's master.
push_commit() { echo "$2" >> "$SEED/$1"; git -C "$SEED" add -- "$1" && git -C "$SEED" commit -qm "$2" && git -C "$SEED" push -q "$ORIGIN" master; }
mk_homes() {
  chmod -R u+rwx "$DH" "$HH" 2>/dev/null; rm -rf "$DH" "$HH"
  mkdir -p "$DH/Projects/Personal" "$HH/Projects/Personal" "$HH/.claude" "$HH/.hermes/scripts"
  chmod 755 "$DH/Projects" "$DH/Projects/Personal"
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

echo local >> "$OLD/README"; git -C "$OLD" commit -qam local
run /bin/bash "$SYNC"
check "S8 hal's clone is ahead of master: exit 4, says where each is" '[ $RC = 4 ] && [ "$(headof "$NEW")" = "$C3" ] && has "(local commits?)" && has "aren'"'"'t both on"'
push_commit README c4; C4=$(git -C "$SEED" rev-parse HEAD)
run /bin/bash "$SYNC"
check "S9 hal's clone has diverged: exit 4" '[ $RC = 4 ] && [ "$(headof "$NEW")" = "$C4" ] && has "fast-forward to ${C4:0:7} failed" && has "aren'"'"'t both on"'

# --- on-hal steps ------------------------------------------------------------------------------
mk_origin; mk_homes; OSHA=$(OLDSHA)

run as_hal acl
check "A0 acl as the wrong account" '[ $RC = 1 ] && has "run this step as \`david\`"'
DOTFILES_DRY_RUN=1 run as_david acl
check "A1 acl dry run" '[ $RC = 0 ] && [ -z "$(acl_of "$DH")" ] && has "will run: /bin/chmod +a \"user:nobody allow search\"" && has "~/Projects"'
run as_david acl
check "A2 acl" '[ $RC = 0 ] && [ "$(acl_of "$DH")" = "user:nobody allow search" ]'
run as_david acl
check "A3 acl again" '[ $RC = 0 ] && has "done already" && [ "$(acl_of "$DH" | wc -l | tr -d " ")" = 1 ]'
/bin/chmod -a "user:nobody allow search" "$DH"; /bin/chmod +a "user:nobody allow list" "$DH"
run as_david acl
check "A4 another entry for the account: refused" '[ $RC = 1 ] && [ "$(acl_of "$DH")" = "user:nobody allow list" ] && has "already has another entry"'
/bin/chmod -a "user:nobody allow list" "$DH"
chmod 700 "$DH/Projects"
run as_david acl
check "A5 clone's folders closed to others: refused" '[ $RC = 1 ] && [ -z "$(acl_of "$DH")" ] && has "isn'"'"'t searchable by other accounts"'
chmod 755 "$DH/Projects"; chmod 600 "$NEW/zsh/zshrc"
run as_david acl
check "A6 a file in the clone closed to others: refused" '[ $RC = 1 ] && has "zsh/zshrc"'
chmod 644 "$NEW/zsh/zshrc"

CK="$HH/.hermes/scripts/dotfiles-sync-check.sh"
run as_hal sync-check-rollback
check "C00 sync-check-rollback before any install" '[ $RC = 0 ] && has "nothing to roll back" && grep -q "echo old" "$CK"'
chmod 000 "$DH"
run as_hal relink
check "R00 relink while the clone is closed: stops at that" '[ $RC = 1 ] && all_into "$OLD" && [ "$(grep -c "^  !" "$OUT")" = 1 ]'
chmod 755 "$DH"; chmod 000 "$DH"
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
run as_hal sync-check
check "C3 sync-check" '[ $RC = 0 ] && cmp -s "$CHECK_SRC" "$CK" && grep -q "echo old" "$CK.pre-vil700" && [ "$(/usr/bin/stat -f %Lp "$CK")" = 755 ]'
run as_hal sync-check
check "C4 sync-check again" '[ $RC = 0 ] && has "done already"'

echo drift >> "$OLD/zsh/zshrc"
run as_hal relink
check "R1 a linked file differs between the clones: refused" '[ $RC = 1 ] && all_into "$OLD" && has "zsh/zshrc differs"'
git -C "$OLD" checkout -q -- zsh/zshrc
echo x > "$NEW/x"; git -C "$NEW" add x; git -C "$NEW" commit -qm x
run as_hal relink
check "R2 clones on different commits: refused" '[ $RC = 1 ] && all_into "$OLD" && has "aren'"'"'t on one commit"'
git -C "$NEW" reset -q --hard HEAD~1
before=$(links_snapshot)
DOTFILES_DRY_RUN=1 run as_hal relink
check "R3 relink dry run" '[ $RC = 0 ] && [ "$(links_snapshot)" = "$before" ] && has "will move 24 link(s)" && has "dead in both clones"'
chmod 555 "$HH"
run as_hal relink
check "R3b relink fails at the first link: exit 1, nothing changed" '[ $RC = 1 ] && all_into "$OLD" && has "Nothing changed on this run"'
chmod 755 "$HH"
chmod 555 "$HH/.config/tmux/scripts"
run as_hal relink
check "R4 relink fails partway: exit 4" '[ $RC = 4 ] && has "link(s) moved on this run, then one failed" && has "Run relink again to finish"'
chmod 755 "$HH/.config/tmux/scripts"
run as_hal relink
check "R5 relink finishes" '[ $RC = 0 ] && all_into "$NEW" && [ "$(readlink "$HH/.claude/CLAUDE.md")" = "$NEW/claude/CLAUDE.md" ] && grep -q "own CLAUDE.md" "$HH/.claude/CLAUDE.md.pre-vil700"'
run as_hal relink
check "R6 relink again" '[ $RC = 0 ] && has "done already"'
run as_hal verify
check "V1 verify" '[ $RC = 0 ] && has "ok:"'
ln -s "$OLD/README" "$HH/.config/stray"
run as_hal verify
check "V2 a stray link into the old clone" '[ $RC = 1 ] && has "links still into"'
run as_hal retire-old-clone
check "T0 retire with a stray link: refused" '[ $RC = 1 ] && [ -d "$OLD/.git" ]'
rm "$HH/.config/stray"

run as_hal sync-check-rollback
check "C5 sync-check-rollback while linked to the shared clone: refused" '[ $RC = 1 ] && cmp -s "$CHECK_SRC" "$CK"'
run as_hal relink-rollback
check "B1 relink-rollback" '[ $RC = 0 ] && all_into "$OLD" && [ ! -L "$HH/.claude/CLAUDE.md" ] && grep -q "own CLAUDE.md" "$HH/.claude/CLAUDE.md" && [ ! -e "$HH/.claude/CLAUDE.md.pre-vil700" ]'
run as_hal relink-rollback
check "B2 relink-rollback again" '[ $RC = 0 ] && has "done already"'
run as_hal sync-check-rollback
check "C6 sync-check-rollback" '[ $RC = 0 ] && grep -q "echo old" "$CK" && [ -f "$CK.pre-vil700" ]'
run as_hal sync-check
check "C7 sync-check after its rollback" '[ $RC = 0 ] && cmp -s "$CHECK_SRC" "$CK"'
run as_hal relink
check "R7 relink after the rollback" '[ $RC = 0 ] && all_into "$NEW"'

DOTFILES_DRY_RUN=1 run as_hal retire-old-clone
check "T1 retire dry run" '[ $RC = 0 ] && [ -d "$OLD/.git" ] && has "will run: /bin/mv"'
run as_hal retire-old-clone
check "T2 retire" '[ $RC = 0 ] && [ ! -e "$OLD" ] && [ -d "$OLD.pre-vil700/.git" ]'
run as_hal retire-old-clone
check "T3 retire again" '[ $RC = 0 ] && has "done already"'
run as_hal relink-rollback
check "B3 relink-rollback after retire: refused" '[ $RC = 1 ] && all_into "$NEW" && has "restore-old-clone first"'
run as_hal restore-old-clone
check "T4 restore-old-clone" '[ $RC = 0 ] && [ -d "$OLD/.git" ] && [ ! -e "$OLD.pre-vil700" ]'

run as_hal nonsense
check "U1 unknown step" '[ $RC = 2 ]'

# --- the sync-check itself, as hal, watching the clone hal's links point into -----------------
# State is now: links into $NEW, both clones on c1, the new check installed.
SC() { HOME="$HH" HERMES_HOME="$HH/.hermes" DOTFILES_SYNC_REMOTE="file://$ORIGIN" DOTFILES_SYNC_MIRROR="${DOTFILES_SYNC_MIRROR:-$T/mirror.git}" \
  DOTFILES_SYNC_STATE="$T/state" /bin/bash "$@"; }
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
git -C "$NEW" pull -q --ff-only
run SC "$CK"
check "K5 pulled: silent" '[ $RC = 0 ] && quiet'
echo "evil" >> "$NEW/zsh/zshrc"
run SC "$CK"
check "K6 tampered file" '[ $RC = 0 ] && has "differ from master* (1): \`zsh/zshrc\`"'
git -C "$NEW" checkout -q -- zsh/zshrc
echo "evil" > "$NEW/zsh/functions/evil.sh"
run SC "$CK"
check "K7 extra file" '[ $RC = 0 ] && has "not on master* (1): \`zsh/functions/evil.sh\`"'
rm "$NEW/zsh/functions/evil.sh"
mv "$NEW/git/gitignore" "$T/gi"; ln -s /etc/hosts "$NEW/git/gitignore"
run SC "$CK"
check "K8 file replaced by a link" '[ $RC = 0 ] && has "*is a link* (1): \`git/gitignore\`"'
rm "$NEW/git/gitignore"; mv "$T/gi" "$NEW/git/gitignore"
echo local >> "$NEW/README"; git -C "$NEW" add README; git -C "$NEW" commit -qm local
run SC "$CK"
check "K9 clone on a commit that isn't on master" '[ $RC = 0 ] && has "isn'"'"'t on master" && has "differ from master* (1): \`README\`"'
git -C "$NEW" reset -q --hard origin/master
run SC "$CK"
check "K10 back in sync: silent" '[ $RC = 0 ] && quiet'
# A hostile url.insteadOf in the watched clone's gitconfig can't redirect the check's fetch.
git init -q --bare "$T/evil.git"; git -C "$SEED" push -q "$T/evil.git" HEAD~1:refs/heads/master
mkdir -p "$T/evilhome"; printf '[url "file://%s"]\n\tinsteadOf = file://%s\n' "$T/evil.git" "$ORIGIN" > "$T/evilhome/.gitconfig"
env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM HOME="$T/evilhome" DOTFILES_CLONE="$NEW" DOTFILES_SYNC_REMOTE="file://$ORIGIN" DOTFILES_SYNC_MIRROR="$T/mirror.git" \
  DOTFILES_SYNC_STATE="$T/state" /bin/bash "$CK" > "$OUT" 2>&1; RC=$?
check "K11 ~/.gitconfig ignored" '[ $RC = 0 ] && quiet'
cp "$CK" "$T/ck-edited.sh"; echo "# local edit" >> "$T/ck-edited.sh"
run SC "$T/ck-edited.sh"
check "K12 installed check isn't master's" '[ $RC = 0 ] && has "this check isn'"'"'t master'"'"'s"'
HOME="$HH" DOTFILES_SYNC_REMOTE="file://$T/nope.git" DOTFILES_SYNC_MIRROR="$T/mirror.git" DOTFILES_SYNC_STATE="$T/state" run /bin/bash "$CK"
check "K13 GitHub unreachable: exit 1 with a reason" '[ $RC = 1 ] && has "fetch of GitHub'"'"'s master failed"'
chmod 000 "$DH"
run SC "$CK"
check "K14 clone unreadable: exit 1 with a reason" '[ $RC = 1 ] && has "can'"'"'t read"'
chmod 755 "$DH"
push_commit helpers/x "touches helpers"
git -C "$NEW" fetch -q
run SC "$CK"
check "K15 install files changed" '[ $RC = 0 ] && has "Install files changed"'

st=$(cat "$T/state"); git -C "$NEW" pull -q --ff-only
DOTFILES_DRY_RUN=1 run SC "$CK"
check "K16 dry run with a mirror: reports, writes no state" '[ $RC = 0 ] && has "[dry-run] compared with" && has "in sync" && [ "$(cat "$T/state")" = "$st" ]'
DOTFILES_DRY_RUN=1 DOTFILES_SYNC_MIRROR="$T/no-mirror.git" run SC "$CK"
check "K17 dry run without a mirror: creates nothing" '[ $RC = 0 ] && has "Would create" && [ ! -e "$T/no-mirror.git" ]'

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
