#!/usr/bin/env bash
#
# hal_shared_clone.sh — the on-hal steps that move `hal` onto `david`'s dotfiles clone, so one
# pull updates both accounts (VIL-700 part 2). Run by hand, one step at a time, in the order
# of "One dotfiles clone on hal" in docs/reference/install-and-server.md. ./install doesn't
# call it. Step 1 of that order, bringing both clones to one commit, runs on the Mac:
# helpers/hal_shared_clone_sync.sh.
#
#   step                 account  from the Mac                                         changes
#   acl                  david    ssh hal 'bash ~/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh acl'
#                                                                                       closes four paths in david's home
#                                                                                       (CLOSE), then one ACL entry on it
#   sync-check           hal      ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh sync-check'
#                                                                                       ~/.hermes/scripts/dotfiles-sync-check.sh
#   relink               hal      (same, with relink)                                  hal's 24 links and ~/.claude/CLAUDE.md
#   verify               hal      (same, with verify)                                  nothing
#   retire-old-clone     hal      (same, with retire-old-clone)                        moves hal's own clone aside
#   rollbacks            hal      relink-rollback, sync-check-rollback, restore-old-clone
#                        david    acl-rollback (only after relink-rollback): removes the entry,
#                                 then puts back the modes the acl step recorded
#
# Each step checks which account runs it, checks the state it expects, and stops with nothing
# changed when the state is anything else. Running a step again is safe: a step that is
# already done says so and exits 0. DOTFILES_DRY_RUN=1 runs the same checks, prints what the
# step would change, and changes nothing; it exits 1 when the checks would stop the real run,
# 0 otherwise.
#
# Exit: 0 done, already done, or a dry run that found nothing in the way. 1 refused, nothing
# changed (verify: something isn't as expected). 2 usage. 4 something was changed and then a
# step failed; the message says what changed and what to run next. Any other code: the shell
# or ssh failed partway, so the code says nothing about the state; run `verify` (or the step
# with DOTFILES_DRY_RUN=1) to see it.
#
# Overrides, for ci/hal-shared-clone-checks.sh only: HAL_SHARED_TEST_USER (stands in for
# `id -un`), HAL_SHARED_TEST_HAL_USER (the account the ACL names), HAL_SHARED_TEST_DAVID_HOME
# (`david`'s home), HAL_SHARED_TEST_OLD_CHECK_SHA (the original sync-check's sha256), and
# HERMES_HOME (as Hermes itself reads it).
# Some messages name paths as ~/... for reading; those are never expanded.
# shellcheck disable=SC2088
set -uo pipefail

# System tools only, whatever the login shell put first on PATH (GNU ln/mv/stat differ).
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH LC_ALL=C

ME=${HAL_SHARED_TEST_USER:-$(id -un)}
HAL_USER=${HAL_SHARED_TEST_HAL_USER:-hal}
d=~david
DAVID_HOME=${HAL_SHARED_TEST_DAVID_HOME:-$d}
REL=Projects/Personal/dotfiles
NEW=$DAVID_HOME/$REL
OLD=$HOME/$REL
OLD_ASIDE=$OLD.pre-vil700
DRY=${DOTFILES_DRY_RUN:-0}
ACE="user:$HAL_USER allow search"
SCRIPTS=${HERMES_HOME:-$HOME/.hermes}/scripts
CHECK=$SCRIPTS/dotfiles-sync-check.sh
CHECK_KEEP=$CHECK.pre-vil700
CHECK_SRC=$NEW/helpers/hal_dotfiles_sync_check.sh
CHECK_MARK='# hal_dotfiles_sync_check.sh — Atlas'
# sha256 of the sync-check that was on hal before this change (read 2026-11-16).
CHECK_OLD_SHA=${HAL_SHARED_TEST_OLD_CHECK_SHA:-34ed9f058ac2d80465ea87a45cab226ad8a0d01d26de168b5d7d8d53c68fef12}
CLAUDE_MD=$HOME/.claude/CLAUDE.md
CLAUDE_KEEP=$CLAUDE_MD.pre-vil700

# hal's links into its clone, as "<link under $HOME> <path in the repo>" (read on hal
# 2026-11-16; `david` has the same 24 plus ~/.claude/CLAUDE.md). herdr/ is gone from the repo,
# so that link is dead in both clones; DEAD_OK names the repo paths allowed to be missing.
DEAD_OK=' herdr/config.toml '
LINKS='.gitconfig git/gitconfig
.config/git/gitattributes git/gitattributes
.config/git/gitconfig.platform git/gitconfig.server
.config/git/gitignore git/gitignore
.config/zsh/.zshenv zsh/zshenv
.config/zsh/.zshrc zsh/zshrc
.config/zsh/.zprofile zsh/zprofile.server
.config/tmux/tmux.conf tmux/tmux.conf
.config/tmux/tmux.general.conf tmux/tmux.general.conf
.config/tmux/tmux.display.conf tmux/tmux.display.conf
.config/tmux/local.conf tmux/local.server.conf
.config/tmux/scripts/clean-copy.sh tmux/scripts/clean-copy.sh
.config/tmux/scripts/location.sh tmux/scripts/location.sh
.config/tmux/scripts/restore-window-meta.sh tmux/scripts/restore-window-meta.sh
.config/tmux/scripts/save-window-meta.sh tmux/scripts/save-window-meta.sh
.config/topgrade.toml topgrade/topgrade.toml
.config/btop/btop.conf btop/btop.conf
.config/lazygit/config.yml lazygit/config.yml
.config/herdr/config.toml herdr/config.toml
.claude/statusline-command.sh claude/statusline-command.sh
.codex/AGENTS.md codex/AGENTS.md
.local/bin/dot bin/dot
.local/bin/op-agent bin/op-agent
.local/bin/wt bin/wt'

PROBLEMS=''
problem() { PROBLEMS="$PROBLEMS$*"$'\n'; echo "  ! $*"; }
say() { echo "  $*"; }
die() { echo "$*" >&2; exit "${2:-1}"; }
refuse_if_problems() {
  [ -z "$PROBLEMS" ] && return 0
  echo "Stopped before changing anything: fix the lines marked ! (or decide about them) first." >&2
  exit 1
}
need_user() { [ "$ME" = "$1" ] || die "run this step as \`$1\` (this is \`$ME\`); nothing changed"; }
dry_stop() {
  [ "$DRY" = 1 ] || return 0
  echo "[dry-run] nothing changed."
  exit 0
}

# head_of <clone>: the commit it's on, read from .git files (no git, so it works on a clone
# another account owns). Empty when it can't be read.
head_of() {
  local g=$1/.git h ref
  h=$(head -n 1 "$g/HEAD" 2>/dev/null) || return 0
  case $h in
    "ref: "*)
      ref=${h#ref: }
      if [ -f "$g/$ref" ]; then head -n 1 "$g/$ref"
      else awk -v r="$ref" '$2 == r { print $1; exit }' "$g/packed-refs" 2>/dev/null
      fi ;;
    *) printf '%s\n' "$h" ;;
  esac
}

# stray_links: sets STRAY to the links in $HOME, outside the expected list, that point into
# hal's own clone. Returns 1 when the scan couldn't read everything it walks (the caller
# treats that as "can't tell", never as "none"). macOS keeps other accounts' and ssh
# sessions' hands off Library, Desktop, Documents, Downloads, Movies, Music and Pictures
# ("Operation not permitted"), so those aren't scanned.
STRAY=''
stray_links() {
  local l found h=$HOME
  STRAY=''
  found=$(find "$h" -xdev \( -path "$h/Library" -o -path "$h/.Trash" -o -path "$h/Desktop" -o -path "$h/Documents" \
    -o -path "$h/Downloads" -o -path "$h/Movies" -o -path "$h/Music" -o -path "$h/Pictures" \
    -o -path "$OLD" -o -path "$OLD_ASIDE" \) -prune -o -type l \( -lname "$OLD" -o -lname "$OLD/*" \) -print) || return 1
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    printf '%s\n' "$LINKS" | awk -v p="${l#"$HOME"/}" '$1 == p { f = 1 } END { exit f }' && STRAY="$STRAY$l "
  done <<< "$found"
  return 0
}

# acl_entries: the ACL entries of $HOME that name the account, one per line; fails when ls does.
acl_entries() {
  local out
  out=$(/bin/ls -led "$HOME") || return 1
  printf '%s\n' "$out" | awk -v u="user:$HAL_USER" '$2 == u { $1 = ""; sub(/^ /, ""); print }'
}

# keep_is_original: $CHECK_KEEP is a regular file with the original check's sha256.
keep_is_original() {
  local sum
  [ -f "$CHECK_KEEP" ] && [ ! -L "$CHECK_KEEP" ] || return 1
  sum=$(shasum -a 256 < "$CHECK_KEEP") || return 1
  [ "${sum%% *}" = "$CHECK_OLD_SHA" ]
}

# installed_check_ok: the installed check is step 3's: an executable regular file (not a link)
# with the shared clone's content, and the original kept as $CHECK_KEEP.
installed_check_ok() {
  [ ! -L "$CHECK" ] && [ -f "$CHECK" ] && [ -x "$CHECK" ] &&
    [ -f "$NEW/helpers/hal_dotfiles_sync_check.sh" ] && cmp -s "$NEW/helpers/hal_dotfiles_sync_check.sh" "$CHECK" &&
    keep_is_original
}

# Is the installed sync-check one this repo wrote (any version)?
check_is_ours() {
  [ -f "$CHECK" ] && [ ! -L "$CHECK" ] &&
    awk -v m="$CHECK_MARK" 'NR <= 5 && index($0, m) == 1 { f = 1 } END { exit !f }' "$CHECK"
}

# ---------------------------------------------------------------------------------------
# Paths in david's home the ACL would otherwise open to hal, and the mode each gets before the
# ACL is set (David's decision, 2026-11-16). Their earlier modes go to $MODES, which
# acl-rollback reads. Every other folder in david's home stays as it is.
CLOSE='.claude/file-history 700
.claude/shell-snapshots 700
scratch 700
env.sh 600'
MODES=$DAVID_HOME/.vil-700-modes-before-acl
CHANGED=0

# mode_of <path>: its permission bits, e.g. 755. Fails when stat does.
mode_of() { stat -f %Lp "$1"; }
# recorded_mode <path under home>: the mode $MODES holds for it, empty if none.
recorded_mode() { [ -f "$MODES" ] && awk -v p="$1" '$1 == p { print $2; exit }' "$MODES"; }

step_acl() {
  need_user david
  echo "acl: close what it would expose, then let \`$HAL_USER\` through $HOME, so it can read the dotfiles clone at $NEW"
  id -u "$HAL_USER" >/dev/null 2>&1 || problem "no account named $HAL_USER"
  [ -d "$NEW/.git" ] || problem "no clone at $NEW"
  # hal reads the clone through the "other" permission bits; the ACL only opens $HOME itself.
  local x bad
  for x in "$DAVID_HOME/Projects" "$DAVID_HOME/Projects/Personal"; do
    [ -n "$(find "$x" -maxdepth 0 -perm -001 2>/dev/null)" ] || problem "$x isn't searchable by other accounts"
  done
  if [ -d "$NEW/.git" ]; then
    if bad=$(find "$NEW" -path "$NEW/.git/objects" -prune -o \( -type d ! -perm -005 -o -type f ! -perm -004 \) -print); then
      bad=$(printf '%s\n' "$bad" | awk 'NF && NR <= 10')
      [ -z "$bad" ] || problem "other accounts can't read these in the clone (first 10): ${bad//$'\n'/ }"
    else
      problem "couldn't check every file in $NEW (find failed)"
    fi
  fi
  # The four paths to close first.
  local p want cur f todo='' closing=' '
  while read -r p want; do
    f=$HOME/$p
    if [ -L "$f" ]; then problem "~/$p is a link; closing it would change what it points at, so that's David's call"; continue; fi
    if [ ! -e "$f" ]; then say "~/$p doesn't exist; skipped"; continue; fi
    cur=$(mode_of "$f") || { problem "can't read the mode of ~/$p"; continue; }
    if [ "$cur" = "$want" ]; then say "~/$p is already $want"; continue; fi
    todo="$todo$p $want $cur"$'\n'; closing="$closing$p "
    say "will close ~/$p: $cur -> $want (the earlier mode is recorded in $MODES)"
  done <<< "$CLOSE"
  # Existing entries that name the account.
  local entries open
  entries=$(acl_entries) || problem "couldn't read the ACL of $HOME"
  if open=$(find "$HOME" -mindepth 1 -maxdepth 1 \( -perm -001 -o -perm -004 \)); then
    say "other accounts, and with the ACL $HAL_USER, can still read these here (the closed paths left out):"
    printf '%s\n' "$open" | sed "s|^$HOME/||" | sort | while IFS= read -r x; do
      case $closing in *" $x "*) ;; *) echo "    ~/$x" ;; esac
    done
  else
    problem "couldn't list what other accounts can read in $HOME"
  fi
  if [ "$entries" = "$ACE" ] && [ -z "$todo" ]; then
    refuse_if_problems
    echo "done already: the paths are closed and $HOME has \"$ACE\"; nothing changed"; exit 0
  fi
  [ -z "$entries" ] || [ "$entries" = "$ACE" ] ||
    problem "$HOME already has another entry for $HAL_USER: $entries (changing it is David's decision)"
  refuse_if_problems
  [ "$entries" = "$ACE" ] || say "will run: /bin/chmod +a \"$ACE\" $HOME"
  dry_stop
  # Close each path, recording its earlier mode first (an entry already there is kept: it's
  # the mode from before the first run). If any of them can't be closed, the ACL isn't set.
  local fail_code
  if [ -n "$todo" ]; then
    while read -r p want cur; do
      [ -n "$p" ] || continue
      fail_code=1; [ "$CHANGED" = 1 ] && fail_code=4
      if [ -z "$(recorded_mode "$p")" ]; then
        local had=0; [ -e "$MODES" ] && had=1
        if ! ( umask 077; printf '%s %s\n' "$p" "$cur" >> "$MODES" ); then
          [ "$had" = 1 ] || [ ! -e "$MODES" ] || fail_code=4
          die "couldn't record the mode of ~/$p in $MODES; the ACL was not set" "$fail_code"
        fi
        CHANGED=1
      fi
      if ! { /bin/chmod "$want" "$HOME/$p" && [ "$(mode_of "$HOME/$p")" = "$want" ]; }; then
        [ "$(mode_of "$HOME/$p" 2>/dev/null)" = "$cur" ] || CHANGED=1
      fi
      [ "$(mode_of "$HOME/$p" 2>/dev/null)" = "$want" ] ||
        die "couldn't close ~/$p to $want; the ACL was not set. Paths closed earlier in this run stay closed; acl-rollback reopens them." "$( [ "$CHANGED" = 1 ] && echo 4 || echo 1 )"
      CHANGED=1
      say "~/$p: $cur -> $want"
    done <<< "$todo"
  fi
  if [ "$entries" != "$ACE" ]; then
    fail_code=1; [ "$CHANGED" = 1 ] && fail_code=4
    /bin/chmod +a "$ACE" "$HOME" || die "chmod +a failed, so the ACL was not set (paths closed on this run stay closed; acl-rollback reopens them)" "$fail_code"
    entries=$(acl_entries) || entries="(couldn't read it)"
    [ "$entries" = "$ACE" ] || die "added, but ls -le shows \"$entries\" for $HAL_USER. Run acl-rollback, look at ls -led ~, then run the acl step again." 4
  fi
  echo "done: the paths are closed and $HOME has \"$ACE\". Next, as $HAL_USER: the sync-check step."
}

step_acl_rollback() {
  need_user david
  echo "acl-rollback: take \"$ACE\" off $HOME, then put back the modes recorded in $MODES"
  echo "  Run it only after relink-rollback (as $HAL_USER): with hal's links in $NEW, removing the entry breaks hal's shell and git. This step can't see hal's links."
  local entries remove=0 p want rec cur f todo=''
  entries=$(acl_entries) || problem "couldn't read the ACL of $HOME"
  if [ "$entries" = "$ACE" ]; then remove=1; say "will run: /bin/chmod -a \"$ACE\" $HOME"
  elif [ -n "$entries" ]; then problem "$HOME has another entry for $HAL_USER: $entries (David's decision)"; fi
  while read -r p want; do
    f=$HOME/$p
    rec=$(recorded_mode "$p") || rec=''
    if [ -z "$rec" ]; then say "no recorded mode for ~/$p; left as it is"; continue; fi
    if [ -L "$f" ]; then problem "~/$p is a link now; left for David"; continue; fi
    if [ ! -e "$f" ]; then say "~/$p doesn't exist; skipped"; continue; fi
    cur=$(mode_of "$f") || { problem "can't read the mode of ~/$p"; continue; }
    if [ "$cur" = "$rec" ]; then say "~/$p is back to $rec already"
    elif [ "$cur" = "$want" ]; then todo="$todo$p $rec"$'\n'; say "will reopen ~/$p: $cur -> $rec"
    else say "~/$p is $cur, neither the closed $want nor the recorded $rec; left as it is"; fi
  done <<< "$CLOSE"
  refuse_if_problems
  if [ "$remove" = 0 ] && [ -z "$todo" ]; then echo "done already: no entry for $HAL_USER, and no recorded mode to put back"; exit 0; fi
  dry_stop
  if [ "$remove" = 1 ]; then
    /bin/chmod -a "$ACE" "$HOME" || die "chmod -a failed; nothing changed"
    entries=$(acl_entries) || entries="(couldn't read it)"
    [ -z "$entries" ] || die "removed, but ls -le still shows \"$entries\" for $HAL_USER; look at ls -led ~, then run acl-rollback again" 4
    CHANGED=1
    say "the entry for $HAL_USER is gone"
  fi
  while read -r p rec; do
    [ -n "$p" ] || continue
    if ! { /bin/chmod "$rec" "$HOME/$p" && [ "$(mode_of "$HOME/$p")" = "$rec" ]; }; then
      [ "$(mode_of "$HOME/$p" 2>/dev/null)" = "$want" ] || CHANGED=1
    fi
    [ "$(mode_of "$HOME/$p" 2>/dev/null)" = "$rec" ] ||
      die "couldn't put ~/$p back to $rec; run acl-rollback again" "$( [ "$CHANGED" = 1 ] && echo 4 || echo 1 )"
    CHANGED=1
    say "~/$p: back to $rec"
  done <<< "$todo"
  echo "done: no entry for $HAL_USER, and the recorded modes are back ($MODES is kept)"
}

# ---------------------------------------------------------------------------------------
step_sync_check() {
  need_user "$HAL_USER"
  echo "sync-check: install $CHECK_SRC as $CHECK"
  [ -f "$CHECK_SRC" ] || problem "no $CHECK_SRC"
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (run the acl step as david first)"
  [ -d "$SCRIPTS" ] || problem "no $SCRIPTS"
  if [ -f "$CHECK" ] && [ ! -L "$CHECK" ] && [ -x "$CHECK" ] && [ -f "$CHECK_SRC" ] && cmp -s "$CHECK_SRC" "$CHECK"; then
    keep_is_original || problem "$CHECK is installed, but $CHECK_KEEP is missing or isn't the original check; restoring it is David's call"
    refuse_if_problems
    echo "done already: $CHECK matches $CHECK_SRC, and the original is $CHECK_KEEP"
    exit 0
  fi
  local keep=0
  if [ -L "$CHECK" ] || [ ! -f "$CHECK" ]; then
    problem "$CHECK is missing or not a regular file"
  elif check_is_ours; then
    say "$CHECK is an older copy of this repo's check; it will be replaced (the original stays in $CHECK_KEEP)"
    keep_is_original || problem "$CHECK_KEEP is missing or isn't the original check, though $CHECK was installed by this step before"
  elif [ -e "$CHECK_KEEP" ] || [ -L "$CHECK_KEEP" ]; then
    # Only after sync-check-rollback: the active script is the kept original.
    if ! keep_is_original || ! cmp -s "$CHECK" "$CHECK_KEEP"; then
      problem "$CHECK_KEEP exists, and either it isn't the original check or $CHECK is neither it nor this repo's check"
    fi
  elif [ "$(shasum -a 256 < "$CHECK" | cut -d' ' -f1)" != "$CHECK_OLD_SHA" ]; then  # unreadable reads as different
    problem "$CHECK isn't the script this step was written against (sha256 differs); compare it with $CHECK_SRC by hand"
  else
    keep=1
    say "will keep the current script as $CHECK_KEEP"
  fi
  refuse_if_problems
  say "will write $CHECK_SRC to $CHECK (through a temp file and a rename)"
  dry_stop
  if [ "$keep" = 1 ]; then
    # A hard link keeps the original file as it is, and fails if the name is taken.
    /bin/ln "$CHECK" "$CHECK_KEEP" || die "couldn't keep $CHECK as $CHECK_KEEP; nothing changed"
  fi
  local tmp=$CHECK.vil700-new.$$
  if ! { /bin/cp "$CHECK_SRC" "$tmp" && /bin/chmod 755 "$tmp" && cmp -s "$CHECK_SRC" "$tmp" && /bin/mv -f "$tmp" "$CHECK"; }; then
    if ! /bin/rm -f "$tmp" || [ -e "$tmp" ]; then
      die "couldn't install $CHECK, and couldn't remove the temporary copy $tmp; remove it by hand, then run the sync-check step again. The active script is unchanged." 4
    fi
    # Exit 4 only when this run made $CHECK_KEEP; otherwise nothing changed.
    [ "$keep" = 1 ] || die "couldn't install $CHECK; nothing changed"
    die "couldn't install $CHECK; the active script is unchanged, and $CHECK_KEEP is a second name for it. Run the sync-check step again." 4
  fi
  cmp -s "$CHECK_SRC" "$CHECK" || die "installed, but $CHECK doesn't match $CHECK_SRC; restore with the sync-check-rollback step" 4
  echo "done: $CHECK is the new check; the original is $CHECK_KEEP. Next: the relink step."
}

step_sync_check_rollback() {
  need_user "$HAL_USER"
  echo "sync-check-rollback: put $CHECK_KEEP back as $CHECK"
  if [ ! -e "$CHECK_KEEP" ] && [ -f "$CHECK" ] && [ "$(shasum -a 256 < "$CHECK" | cut -d' ' -f1)" = "$CHECK_OLD_SHA" ]; then
    echo "nothing to roll back: $CHECK is the original, and the sync-check step never ran"; exit 0
  fi
  keep_is_original || problem "no $CHECK_KEEP holding the original check to restore"
  # The original runs git in the clone the zshrc link points at, which only works in hal's own.
  case $(readlink "$HOME/.config/zsh/.zshrc" 2>/dev/null) in
    "$OLD"/*) ;;
    *) problem "~/.config/zsh/.zshrc doesn't point into $OLD, where the original check works; run relink-rollback first" ;;
  esac
  if [ -f "$CHECK_KEEP" ] && [ -f "$CHECK" ] && cmp -s "$CHECK_KEEP" "$CHECK"; then
    refuse_if_problems; echo "done already: $CHECK is the original"; exit 0
  fi
  refuse_if_problems
  say "will copy $CHECK_KEEP over $CHECK (through a temp file and a rename; $CHECK_KEEP stays)"
  dry_stop
  local tmp=$CHECK.vil700-rb.$$
  if ! { /bin/cp -p "$CHECK_KEEP" "$tmp" && cmp -s "$CHECK_KEEP" "$tmp" && /bin/mv -f "$tmp" "$CHECK"; }; then
    if ! /bin/rm -f "$tmp" || [ -e "$tmp" ]; then
      die "couldn't restore $CHECK, and couldn't remove the temporary copy $tmp; remove it by hand, then run sync-check-rollback again. The active script is unchanged." 4
    fi
    die "couldn't restore $CHECK; the active script is unchanged"
  fi
  cmp -s "$CHECK_KEEP" "$CHECK" || die "restored, but $CHECK doesn't match $CHECK_KEEP; look at both, then run sync-check-rollback again" 4
  echo "done: $CHECK is the original again"
}

# ---------------------------------------------------------------------------------------
# target_ok <link> <repo path>: the shared clone's file is fit to link to: readable, the same
# as hal's own clone's (both clones are on one commit), or missing in both where DEAD_OK allows.
target_ok() {
  local l=$1 r=$2
  if [ -e "$NEW/$r" ]; then
    [ -r "$NEW/$r" ] || { problem "$NEW/$r isn't readable as $ME"; return 1; }
    [ -e "$OLD/$r" ] || { problem "$OLD/$r is missing, but $NEW/$r exists"; return 1; }
    if ! cmp -s "$OLD/$r" "$NEW/$r"; then
      problem "$r differs between the two clones (run the Mac's sync step first)"; return 1
    fi
  elif [ -e "$OLD/$r" ]; then
    problem "$NEW/$r is missing (or unreadable as $ME), but $OLD/$r exists"; return 1
  else
    case $DEAD_OK in
      *" $r "*) say "~/$l is dead in both clones ($r) and stays dead" ;;
      *) problem "$r is missing (or unreadable as $ME) in both clones"; return 1 ;;
    esac
  fi
}

# plan_forward: check every expected link for relink, the ones already moved included, and
# set TODO (lines "<link> <target>") and DONE_N. Problems go to problem().
plan_forward() {
  local l r t
  TODO='' DONE_N=0
  while read -r l r; do
    if [ ! -L "$HOME/$l" ]; then problem "~/$l isn't a link"; continue; fi
    t=$(readlink "$HOME/$l")
    case $t in
      "$NEW/$r") target_ok "$l" "$r" && DONE_N=$((DONE_N + 1)) ;;
      "$OLD/$r") target_ok "$l" "$r" && TODO="$TODO$l $NEW/$r"$'\n' ;;
      *) problem "~/$l points at $t, not $OLD/$r or $NEW/$r" ;;
    esac
  done <<< "$LINKS"
}

# plan_back: check every expected link for relink-rollback. It never compares the clones:
# after a pull as david they differ, and that's when a rollback may be wanted. A link into
# the shared clone goes back when hal's own clone still has the file (or DEAD_OK allows it).
plan_back() {
  local l r t
  TODO='' DONE_N=0
  while read -r l r; do
    if [ ! -L "$HOME/$l" ]; then problem "~/$l isn't a link"; continue; fi
    t=$(readlink "$HOME/$l")
    case $t in
      "$OLD/$r") DONE_N=$((DONE_N + 1)) ;;
      "$NEW/$r")
        if [ -e "$OLD/$r" ] || case $DEAD_OK in *" $r "*) true ;; *) false ;; esac; then
          TODO="$TODO$l $OLD/$r"$'\n'
        else
          problem "$OLD/$r is missing, so ~/$l can't go back to it"
        fi ;;
      *) problem "~/$l points at $t, not $NEW/$r or $OLD/$r" ;;
    esac
  done <<< "$LINKS"
}

# move_links: re-point each TODO link by renaming a new link over it (atomic per link).
# MOVED counts the links this run changed, so a failure can say whether anything did.
MOVED=0 TMPLEFT=0
move_links() {
  local l t tmp
  while read -r l t; do
    [ -n "$l" ] || continue
    tmp=$HOME/$l.vil700-tmp.$$
    if ! { /bin/ln -s "$t" "$tmp" && /bin/mv -fh "$tmp" "$HOME/$l"; }; then
      if ! /bin/rm -f "$tmp" || [ -e "$tmp" ] || [ -L "$tmp" ]; then
        TMPLEFT=1; echo "couldn't remove the temporary link $tmp; remove it by hand" >&2
      fi
      echo "failed at ~/$l after moving $MOVED link(s) on this run" >&2
      return 1
    fi
    # The rename happened, so it counts as a change even if the read-back below fails.
    MOVED=$((MOVED + 1))
    [ "$(readlink "$HOME/$l")" = "$t" ] || { echo "~/$l was renamed, but doesn't read back as $t" >&2; return 1; }
    say "~/$l -> $t"
  done <<< "$TODO"
}
# changed_code: 4 when this run changed something, 1 when it didn't.
changed_code() { if [ "$MOVED" -gt 0 ] || [ "$TMPLEFT" = 1 ] || [ "${1:-0}" = 1 ]; then echo 4; else echo 1; fi; }

step_relink() {
  need_user "$HAL_USER"
  echo "relink: point $HAL_USER's links from $OLD to $NEW, and link ~/.claude/CLAUDE.md"
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (run the acl step as david first)"
  [ -d "$OLD" ] || problem "no $OLD (was it moved aside already?)"
  refuse_if_problems
  # Done first: once every link is moved, a pull since (the clones no longer on one commit)
  # doesn't turn a finished relink into a refusal.
  if all_moved; then echo "done already: all 24 links and ~/.claude/CLAUDE.md point into $NEW"; exit 0; fi
  local ho hn
  ho=$(head_of "$OLD") hn=$(head_of "$NEW")
  if [ -z "$ho" ] || [ "$ho" != "$hn" ]; then
    problem "the clones aren't on one commit ($OLD: ${ho:-?}, $NEW: ${hn:-?}); run the Mac's sync step first"
  fi
  installed_check_ok || problem "$CHECK isn't step 3's (an executable copy of the clone's, with the original kept); run the sync-check step first"
  plan_forward
  # CLAUDE.md: a regular file becomes a link; the file is kept beside it.
  local claude=0
  if [ -L "$CLAUDE_MD" ]; then
    if [ "$(readlink "$CLAUDE_MD")" = "$NEW/claude/CLAUDE.md" ] && [ -f "$CLAUDE_KEEP" ]; then DONE_N=$((DONE_N + 1))
    else problem "~/.claude/CLAUDE.md is a link to $(readlink "$CLAUDE_MD") (or $CLAUDE_KEEP is missing)"; fi
  elif [ -f "$CLAUDE_MD" ]; then
    # Taken by another file is a stop; a second name for this same file is an earlier run
    # that stopped between keeping it and linking the name.
    if { [ -e "$CLAUDE_KEEP" ] || [ -L "$CLAUDE_KEEP" ]; } && ! [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ]; then
      problem "$CLAUDE_KEEP already exists, and isn't ~/.claude/CLAUDE.md"
    elif [ ! -r "$NEW/claude/CLAUDE.md" ]; then problem "$NEW/claude/CLAUDE.md isn't readable as $ME"
    else claude=1; say "~/.claude/CLAUDE.md ($(wc -c < "$CLAUDE_MD" | tr -d ' ') bytes) will be kept as $CLAUDE_KEEP, and the name linked to $NEW/claude/CLAUDE.md"
    fi
  else
    problem "~/.claude/CLAUDE.md is missing"
  fi
  if ! stray_links; then say "couldn't scan all of $HOME for other links into $OLD (retire-old-clone stops on that)"
  elif [ -n "$STRAY" ]; then say "not in this step's list, left pointing into $OLD (retire-old-clone stops on them): $STRAY"; fi
  refuse_if_problems
  local todo_n
  todo_n=$(printf '%s' "$TODO" | grep -c .)
  if [ "$todo_n" = 0 ] && [ "$claude" = 0 ]; then echo "done already: all $DONE_N links point into $NEW"; exit 0; fi
  say "will move $todo_n link(s); $DONE_N already done"
  if [ "$DRY" = 1 ]; then printf '%s' "$TODO" | sed 's/^/    ~\//; s/ / -> /'; fi
  dry_stop
  if ! move_links; then
    [ "$(changed_code)" = 4 ] || die "Nothing changed on this run."
    die "$MOVED link(s) moved on this run, then one failed. Run relink again to finish, or relink-rollback to undo." 4
  fi
  if [ "$claude" = 1 ]; then
    local tmp=$CLAUDE_MD.vil700-tmp.$$ kept=0
    if ! [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ]; then
      /bin/ln "$CLAUDE_MD" "$CLAUDE_KEEP" ||
        die "couldn't keep ~/.claude/CLAUDE.md as $CLAUDE_KEEP, so it is unchanged ($MOVED link(s) moved on this run). Run relink again, or relink-rollback." "$(changed_code)"
      kept=1
    fi
    if ! { /bin/ln -s "$NEW/claude/CLAUDE.md" "$tmp" && /bin/mv -f "$tmp" "$CLAUDE_MD" &&
           [ "$(readlink "$CLAUDE_MD")" = "$NEW/claude/CLAUDE.md" ]; }; then
      if ! /bin/rm -f "$tmp" || [ -e "$tmp" ] || [ -L "$tmp" ]; then
        TMPLEFT=1; echo "couldn't remove the temporary link $tmp; remove it by hand" >&2
      fi
      die "~/.claude/CLAUDE.md is unchanged, and $CLAUDE_KEEP is a second name for it ($MOVED link(s) moved on this run). Run relink again to finish, or relink-rollback to undo." "$(changed_code "$kept")"
    fi
    say "~/.claude/CLAUDE.md -> $NEW/claude/CLAUDE.md (old file: $CLAUDE_KEEP)"
  fi
  echo "done: $HAL_USER's links point into $NEW. Next: the verify step."
}

step_relink_rollback() {
  need_user "$HAL_USER"
  echo "relink-rollback: point $HAL_USER's links back into $OLD, and restore ~/.claude/CLAUDE.md"
  [ -d "$OLD" ] || problem "no $OLD; if it was moved aside, run restore-old-clone first"
  plan_back
  local claude=0
  if [ -L "$CLAUDE_MD" ] && [ "$(readlink "$CLAUDE_MD")" = "$NEW/claude/CLAUDE.md" ]; then
    if [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ]; then claude=1; say "will put $CLAUDE_KEEP back as ~/.claude/CLAUDE.md"
    else problem "$CLAUDE_KEEP is missing, so ~/.claude/CLAUDE.md can't be restored"; fi
  elif [ -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    if [ -e "$CLAUDE_KEEP" ] || [ -L "$CLAUDE_KEEP" ]; then
      if [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ]; then
        say "$CLAUDE_KEEP is a second name for ~/.claude/CLAUDE.md, left by a relink that stopped; it's left as it is"
      else
        problem "both ~/.claude/CLAUDE.md and $CLAUDE_KEEP are files; which to keep is David's decision"
      fi
    fi
    DONE_N=$((DONE_N + 1))
  else
    problem "~/.claude/CLAUDE.md is neither the link relink made nor a file"
  fi
  refuse_if_problems
  local todo_n
  todo_n=$(printf '%s' "$TODO" | grep -c .)
  if [ "$todo_n" = 0 ] && [ "$claude" = 0 ]; then echo "done already: the links point into $OLD"; exit 0; fi
  say "will move $todo_n link(s) back; $DONE_N already there"
  dry_stop
  if ! move_links; then
    [ "$(changed_code)" = 4 ] || die "Nothing changed on this run."
    die "$MOVED link(s) moved back on this run, then one failed. Run relink-rollback again to finish." 4
  fi
  if [ "$claude" = 1 ]; then
    { /bin/mv -f "$CLAUDE_KEEP" "$CLAUDE_MD" && [ -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; } ||
      die "~/.claude/CLAUDE.md is still the link, and $CLAUDE_KEEP holds the file ($MOVED link(s) moved back on this run). Run relink-rollback again." "$(changed_code)"
    say "~/.claude/CLAUDE.md is the file again"
  fi
  echo "done: $HAL_USER's links point into $OLD again"
}

# ---------------------------------------------------------------------------------------
# all_moved: the relink is complete (checked quietly, for relink's "done already").
all_moved() {
  local l r
  while read -r l r; do
    [ -L "$HOME/$l" ] && [ "$(readlink "$HOME/$l")" = "$NEW/$r" ] || return 1
  done <<< "$LINKS"
  [ "$(readlink "$CLAUDE_MD" 2>/dev/null)" = "$NEW/claude/CLAUDE.md" ] && [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ]
}

# links_moved: every expected link, and ~/.claude/CLAUDE.md, point into the shared clone, the
# file CLAUDE.md replaced is kept, and no other link in $HOME points into hal's own clone.
links_moved() {
  local l r t
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (is the ACL on $DAVID_HOME in place?)"
  while read -r l r; do
    t=$(readlink "$HOME/$l" 2>/dev/null)
    [ "$t" = "$NEW/$r" ] || { problem "~/$l -> ${t:-(not a link)}, not $NEW/$r"; continue; }
    if [ ! -e "$t" ]; then
      case $DEAD_OK in
        *" $r "*) say "~/$l is dead: $r isn't in the clone" ;;
        *) problem "$t is missing (or unreadable as $ME)" ;;
      esac
    elif [ ! -r "$t" ]; then problem "$t isn't readable as $ME"; fi
  done <<< "$LINKS"
  [ "$(readlink "$CLAUDE_MD" 2>/dev/null)" = "$NEW/claude/CLAUDE.md" ] || problem "~/.claude/CLAUDE.md isn't a link to $NEW/claude/CLAUDE.md"
  [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ] || problem "no $CLAUDE_KEEP file"
  if ! stray_links; then problem "couldn't scan all of $HOME for links into $OLD"
  elif [ -n "$STRAY" ]; then problem "links still into $OLD: $STRAY"; fi
}

# verify_checks: links_moved, and the installed check is step 3's for the clone as it is now.
verify_checks() {
  links_moved
  installed_check_ok || problem "$CHECK isn't step 3's: an executable copy of $NEW/helpers/hal_dotfiles_sync_check.sh, with the original kept as $CHECK_KEEP (run the sync-check step)"
}

step_verify() {
  need_user "$HAL_USER"
  echo "verify: $HAL_USER runs from $NEW"
  verify_checks
  if [ -n "$PROBLEMS" ]; then echo "not as expected; see the lines marked !" >&2; exit 1; fi
  if [ -d "$OLD" ]; then say "hal's own clone is still at $OLD (retire-old-clone moves it aside)"
  elif [ -d "$OLD_ASIDE" ]; then say "hal's old clone is at $OLD_ASIDE"; fi
  echo "ok: all 24 links and ~/.claude/CLAUDE.md point into $NEW, and the new sync-check is installed"
}

# ---------------------------------------------------------------------------------------
step_retire_old_clone() {
  need_user "$HAL_USER"
  echo "retire-old-clone: move $OLD aside to $OLD_ASIDE (nothing is deleted)"
  if [ ! -e "$OLD" ] && [ ! -L "$OLD" ] && [ -d "$OLD_ASIDE/.git" ]; then
    # Done is about the move, so a pull since (which can make the installed check stale) doesn't
    # turn it into a refusal; verify reports a stale check on its own.
    links_moved
    refuse_if_problems
    echo "done already: the old clone is at $OLD_ASIDE, and every link points into $NEW"; exit 0
  fi
  verify_checks
  [ -d "$OLD/.git" ] || problem "no clone at $OLD"
  [ ! -e "$OLD_ASIDE" ] && [ ! -L "$OLD_ASIDE" ] || problem "$OLD_ASIDE already exists"
  local since st un sl
  if [ "$(readlink "$HOME/.config/zsh/.zshrc" 2>/dev/null)" = "$NEW/zsh/zshrc" ]; then
    since=$(stat -f %Sm -t '%Y-%m-%d %H:%M %Z' "$HOME/.config/zsh/.zshrc" 2>/dev/null)
    say "the links were moved at ${since:-?} (the zshrc link's time)"
  fi
  if [ -d "$OLD/.git" ]; then
    # What the old clone holds that GitHub may not; moving it keeps all of it. Each read must
    # work, so the list printed is the whole of it.
    if st=$(git -C "$OLD" --no-optional-locks status --short --branch) &&
       un=$(git -C "$OLD" log --oneline --branches --not --remotes) &&
       sl=$(git -C "$OLD" stash list); then
      say "in the old clone (kept as it is):"
      printf '%s\n' "$st" | sed 's/^/    /'
      [ -z "$un" ] || printf '%s\n' "$un" | sed 's/^/    not on any remote: /'
      [ -z "$sl" ] || printf '%s\n' "$sl" | sed 's/^/    stash: /'
    else
      problem "couldn't read the old clone's state (git status, log or stash list failed)"
    fi
  fi
  refuse_if_problems
  say "will run: /bin/mv $OLD $OLD_ASIDE"
  dry_stop
  /bin/mv "$OLD" "$OLD_ASIDE" || die "mv failed; check that $OLD is still there"
  [ ! -e "$OLD" ] && [ -d "$OLD_ASIDE/.git" ] || die "after the mv, $OLD or $OLD_ASIDE isn't as expected. Look at both; restore-old-clone undoes the move once $OLD_ASIDE holds the clone and $OLD is gone." 4
  echo "done: the old clone is at $OLD_ASIDE. To undo: the restore-old-clone step."
}

step_restore_old_clone() {
  need_user "$HAL_USER"
  echo "restore-old-clone: move $OLD_ASIDE back to $OLD"
  if [ -d "$OLD/.git" ] && [ ! -e "$OLD_ASIDE" ] && [ ! -L "$OLD_ASIDE" ]; then echo "done already: the old clone is at $OLD"; exit 0; fi
  [ -d "$OLD_ASIDE/.git" ] || problem "no clone at $OLD_ASIDE"
  [ ! -e "$OLD" ] && [ ! -L "$OLD" ] || problem "$OLD already exists"
  refuse_if_problems
  say "will run: /bin/mv $OLD_ASIDE $OLD"
  dry_stop
  /bin/mv "$OLD_ASIDE" "$OLD" || die "mv failed; check that $OLD_ASIDE is still there"
  [ -d "$OLD/.git" ] && [ ! -e "$OLD_ASIDE" ] || die "after the mv, $OLD or $OLD_ASIDE isn't as expected; look at both, then run restore-old-clone again" 4
  echo "done: the old clone is at $OLD again"
}

case ${1:-} in
  acl) step_acl ;;
  acl-rollback) step_acl_rollback ;;
  sync-check) step_sync_check ;;
  sync-check-rollback) step_sync_check_rollback ;;
  relink) step_relink ;;
  relink-rollback) step_relink_rollback ;;
  verify) step_verify ;;
  retire-old-clone) step_retire_old_clone ;;
  restore-old-clone) step_restore_old_clone ;;
  *) die "usage: $0 acl|acl-rollback|sync-check|sync-check-rollback|relink|relink-rollback|verify|retire-old-clone|restore-old-clone" 2 ;;
esac
