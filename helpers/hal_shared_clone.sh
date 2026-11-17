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
#                                                                                       one ACL entry on david's home
#   sync-check           hal      ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh sync-check'
#                                                                                       ~/.hermes/scripts/dotfiles-sync-check.sh
#   relink               hal      (same, with relink)                                  hal's 24 links and ~/.claude/CLAUDE.md
#   verify               hal      (same, with verify)                                  nothing
#   retire-old-clone     hal      (same, with retire-old-clone)                        moves hal's own clone aside
#   rollbacks            hal      relink-rollback, sync-check-rollback, restore-old-clone
#   The ACL comes off with: ssh hal '/bin/chmod -a "user:hal allow search" ~'  (only after relink-rollback)
#
# Each step checks which account runs it, checks the state it expects, and stops with nothing
# changed when the state is anything else. Running a step again is safe: a step that is
# already done says so and exits 0. DOTFILES_DRY_RUN=1 runs the same checks, prints what the
# step would change, and changes nothing; it exits with the code the real run would stop with.
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
# Messages name paths as ~/..., for reading; they are never expanded.
# shellcheck disable=SC2088
set -uo pipefail

# System tools only, whatever the login shell put first on PATH (GNU ln/mv/stat differ).
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH LC_ALL=C

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)
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
CHECK_SRC=$SELF_DIR/hal_dotfiles_sync_check.sh
CHECK_MARK='# hal_dotfiles_sync_check.sh — Atlas'
# sha256 of the sync-check that was on hal before this change (read 2026-11-16).
CHECK_OLD_SHA=${HAL_SHARED_TEST_OLD_CHECK_SHA:-34ed9f058ac2d80465ea87a45cab226ad8a0d01d26de168b5d7d8d53c68fef12}
CLAUDE_MD=$HOME/.claude/CLAUDE.md
CLAUDE_KEEP=$CLAUDE_MD.pre-vil700

# hal's links into its clone, as "<link under $HOME> <path in the repo>" (read on hal
# 2026-11-16; `david` has the same 24 plus ~/.claude/CLAUDE.md). herdr/ is gone from the repo,
# so that link is dead in both clones.
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

# Links in $HOME, outside the expected list, that point into hal's own clone.
stray_links() {
  local l
  find "$HOME" -xdev \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -path "$OLD" -o -path "$OLD_ASIDE" \) -prune \
    -o -type l \( -lname "$OLD" -o -lname "$OLD/*" \) -print 2>/dev/null |
  while IFS= read -r l; do
    printf '%s\n' "$LINKS" | awk -v p="${l#"$HOME"/}" '$1 == p { f = 1 } END { exit f }' && printf '%s\n' "$l"
  done
}

# Is the installed sync-check one this repo wrote (any version)?
check_is_ours() {
  [ -f "$CHECK" ] && [ ! -L "$CHECK" ] &&
    awk -v m="$CHECK_MARK" 'NR <= 5 && index($0, m) == 1 { f = 1 } END { exit !f }' "$CHECK"
}

# ---------------------------------------------------------------------------------------
step_acl() {
  need_user david
  echo "acl: let \`$HAL_USER\` through $HOME, so it can read the dotfiles clone at $NEW"
  id -u "$HAL_USER" >/dev/null 2>&1 || problem "no account named $HAL_USER"
  [ -d "$NEW/.git" ] || problem "no clone at $NEW"
  # hal reads the clone through the "other" permission bits; the ACL only opens $HOME itself.
  local x bad
  for x in "$DAVID_HOME/Projects" "$DAVID_HOME/Projects/Personal"; do
    [ -n "$(find "$x" -maxdepth 0 -perm -001 2>/dev/null)" ] || problem "$x isn't searchable by other accounts"
  done
  if [ -d "$NEW/.git" ]; then
    bad=$(find "$NEW" -path "$NEW/.git/objects" -prune -o \( -type d ! -perm -005 -o -type f ! -perm -004 \) -print 2>/dev/null | head -n 10)
    [ -z "$bad" ] || problem "other accounts can't read these in the clone (first 10): ${bad//$'\n'/ }"
  fi
  # Existing entries that name the account.
  local entries
  entries=$(/bin/ls -led "$HOME" | awk -v u="user:$HAL_USER" '$2 == u { $1 = ""; sub(/^ /, ""); print }')
  say "the ACL also lets $HAL_USER into what other accounts can already read here:"
  find "$HOME" -mindepth 1 -maxdepth 1 \( -perm -001 -o -perm -004 \) 2>/dev/null | sed "s|^$HOME/|    ~/|" | sort
  if [ "$entries" = "$ACE" ]; then
    refuse_if_problems
    echo "done already: $HOME has \"$ACE\"; nothing changed"; exit 0
  fi
  [ -z "$entries" ] || problem "$HOME already has another entry for $HAL_USER: $entries (changing it is David's decision)"
  refuse_if_problems
  say "will run: /bin/chmod +a \"$ACE\" $HOME"
  dry_stop
  /bin/chmod +a "$ACE" "$HOME" || die "chmod +a failed; nothing changed"
  entries=$(/bin/ls -led "$HOME" | awk -v u="user:$HAL_USER" '$2 == u { $1 = ""; sub(/^ /, ""); print }')
  [ "$entries" = "$ACE" ] || die "added, but ls -le shows \"$entries\" for $HAL_USER. Undo with /bin/chmod -a \"$ACE\" ~, look at ls -led ~, then run the acl step again." 4
  echo "done: $HOME has \"$ACE\". Next, as $HAL_USER: the sync-check step."
}

# ---------------------------------------------------------------------------------------
step_sync_check() {
  need_user "$HAL_USER"
  echo "sync-check: install $CHECK_SRC as $CHECK"
  [ -f "$CHECK_SRC" ] || problem "no $CHECK_SRC"
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (run the acl step as david first)"
  [ -d "$SCRIPTS" ] || problem "no $SCRIPTS"
  if [ -f "$CHECK" ] && [ -f "$CHECK_SRC" ] && cmp -s "$CHECK_SRC" "$CHECK"; then
    refuse_if_problems
    if [ -f "$CHECK_KEEP" ]; then echo "done already: $CHECK matches $CHECK_SRC; the old one is $CHECK_KEEP"
    else echo "done already: $CHECK matches $CHECK_SRC (no $CHECK_KEEP)"; fi
    exit 0
  fi
  local keep=0
  if [ -L "$CHECK" ] || [ ! -f "$CHECK" ]; then
    problem "$CHECK is missing or not a regular file"
  elif check_is_ours; then
    say "$CHECK is an older copy of this repo's check; it will be replaced (the original stays in $CHECK_KEEP)"
    [ -f "$CHECK_KEEP" ] || problem "$CHECK_KEEP is missing, though $CHECK was installed by this step before"
  elif [ -e "$CHECK_KEEP" ] || [ -L "$CHECK_KEEP" ]; then
    # Only after sync-check-rollback: the active script is the kept original.
    cmp -s "$CHECK" "$CHECK_KEEP" || problem "$CHECK_KEEP exists and $CHECK is neither it nor this repo's check"
  elif [ "$(shasum -a 256 < "$CHECK" | cut -d' ' -f1)" != "$CHECK_OLD_SHA" ]; then
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
    /bin/rm -f "$tmp"
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
  [ -f "$CHECK_KEEP" ] && [ ! -L "$CHECK_KEEP" ] || problem "no $CHECK_KEEP to restore"
  # The original runs git in the clone the zshrc link points at, which only works in hal's own.
  case $(readlink "$HOME/.config/zsh/.zshrc" 2>/dev/null) in
    "$NEW"/*) problem "hal's links point into $NEW, where the original check fails; run relink-rollback first" ;;
  esac
  if [ -f "$CHECK_KEEP" ] && [ -f "$CHECK" ] && cmp -s "$CHECK_KEEP" "$CHECK"; then
    refuse_if_problems; echo "done already: $CHECK is the original"; exit 0
  fi
  refuse_if_problems
  say "will copy $CHECK_KEEP over $CHECK (through a temp file and a rename; $CHECK_KEEP stays)"
  dry_stop
  local tmp=$CHECK.vil700-rb.$$
  if ! { /bin/cp -p "$CHECK_KEEP" "$tmp" && cmp -s "$CHECK_KEEP" "$tmp" && /bin/mv -f "$tmp" "$CHECK"; }; then
    /bin/rm -f "$tmp"
    die "couldn't restore $CHECK; the active script is unchanged"
  fi
  echo "done: $CHECK is the original again"
}

# ---------------------------------------------------------------------------------------
# plan_links <to> <from>: check every expected link and print what moving it from <from> to
# <to> would do. Sets TODO (lines "<link> <target>") and DONE_N. Problems go to problem().
plan_links() {
  local to=$1 from=$2 l r t
  TODO='' DONE_N=0
  while read -r l r; do
    t=$(readlink "$HOME/$l" 2>/dev/null)
    if [ ! -L "$HOME/$l" ]; then problem "~/$l isn't a link"; continue; fi
    if [ "$t" = "$to/$r" ]; then DONE_N=$((DONE_N + 1)); continue; fi
    [ "$t" = "$from/$r" ] || { problem "~/$l points at $t, not $from/$r"; continue; }
    if [ -e "$to/$r" ]; then
      [ -r "$to/$r" ] || { problem "$to/$r isn't readable as $ME"; continue; }
      if [ -e "$from/$r" ] && ! cmp -s "$from/$r" "$to/$r"; then
        problem "$r differs between the two clones (run the Mac's sync step first)"; continue
      fi
    elif [ -e "$from/$r" ]; then
      problem "$to/$r is missing (or unreadable as $ME), but $from/$r exists"; continue
    else
      say "~/$l is dead in both clones ($r); it moves anyway, and stays dead"
    fi
    TODO="$TODO$l $to/$r"$'\n'
  done <<< "$LINKS"
}

# move_links: re-point each TODO link by renaming a new link over it (atomic per link).
# MOVED counts the links this run changed, so a failure can say whether anything did.
MOVED=0
move_links() {
  local l t tmp
  while read -r l t; do
    [ -n "$l" ] || continue
    tmp=$HOME/$l.vil700-tmp.$$
    if ! { /bin/ln -s "$t" "$tmp" && /bin/mv -fh "$tmp" "$HOME/$l" && [ "$(readlink "$HOME/$l")" = "$t" ]; }; then
      /bin/rm -f "$tmp"
      echo "failed at ~/$l after moving $MOVED link(s) on this run" >&2
      return 1
    fi
    MOVED=$((MOVED + 1)); say "~/$l -> $t"
  done <<< "$TODO"
}
# changed_code: 4 when this run changed something, 1 when it didn't.
changed_code() { if [ "$MOVED" -gt 0 ] || [ "${1:-0}" = 1 ]; then echo 4; else echo 1; fi; }

step_relink() {
  need_user "$HAL_USER"
  echo "relink: point $HAL_USER's links from $OLD to $NEW, and link ~/.claude/CLAUDE.md"
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (run the acl step as david first)"
  [ -d "$OLD" ] || problem "no $OLD (was it moved aside already?)"
  refuse_if_problems
  local ho hn
  ho=$(head_of "$OLD") hn=$(head_of "$NEW")
  if [ -z "$ho" ] || [ "$ho" != "$hn" ]; then
    problem "the clones aren't on one commit ($OLD: ${ho:-?}, $NEW: ${hn:-?}); run the Mac's sync step first"
  fi
  if check_is_ours; then :; else problem "$CHECK is still the original, which fails once the links move; run the sync-check step first"; fi
  plan_links "$NEW" "$OLD"
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
  local stray
  stray=$(stray_links)
  [ -z "$stray" ] || say "not in this step's list, left pointing into $OLD (retire-old-clone stops on them): ${stray//$'\n'/ }"
  refuse_if_problems
  local todo_n
  todo_n=$(printf '%s' "$TODO" | grep -c .)
  if [ "$todo_n" = 0 ] && [ "$claude" = 0 ]; then echo "done already: all $DONE_N links point into $NEW"; exit 0; fi
  say "will move $todo_n link(s); $DONE_N already done"
  if [ "$DRY" = 1 ]; then printf '%s' "$TODO" | sed 's/^/    ~\//; s/ / -> /'; fi
  dry_stop
  if ! move_links; then
    [ "$MOVED" -gt 0 ] || die "Nothing changed on this run."
    die "$MOVED link(s) moved on this run, then one failed. Run relink again to finish, or relink-rollback to undo." 4
  fi
  if [ "$claude" = 1 ]; then
    local tmp=$CLAUDE_MD.vil700-tmp.$$ kept=0
    if ! [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ]; then
      /bin/ln "$CLAUDE_MD" "$CLAUDE_KEEP" ||
        die "couldn't keep ~/.claude/CLAUDE.md as $CLAUDE_KEEP, so it is unchanged ($MOVED link(s) moved on this run). Run relink again, or relink-rollback." "$(changed_code)"
      kept=1
    fi
    if ! { /bin/ln -s "$NEW/claude/CLAUDE.md" "$tmp" && /bin/mv -f "$tmp" "$CLAUDE_MD"; }; then
      /bin/rm -f "$tmp"
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
  plan_links "$OLD" "$NEW"
  local claude=0
  if [ -L "$CLAUDE_MD" ] && [ "$(readlink "$CLAUDE_MD")" = "$NEW/claude/CLAUDE.md" ]; then
    if [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ]; then claude=1; say "will put $CLAUDE_KEEP back as ~/.claude/CLAUDE.md"
    else problem "$CLAUDE_KEEP is missing, so ~/.claude/CLAUDE.md can't be restored"; fi
  elif [ -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    if [ -e "$CLAUDE_KEEP" ]; then
      [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ] || problem "both ~/.claude/CLAUDE.md and $CLAUDE_KEEP are files; which to keep is David's decision"
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
    [ "$MOVED" -gt 0 ] || die "Nothing changed on this run."
    die "$MOVED link(s) moved back on this run, then one failed. Run relink-rollback again to finish." 4
  fi
  if [ "$claude" = 1 ]; then
    /bin/mv -f "$CLAUDE_KEEP" "$CLAUDE_MD" ||
      die "~/.claude/CLAUDE.md is still the link, and $CLAUDE_KEEP holds the file ($MOVED link(s) moved back on this run). Run relink-rollback again." "$(changed_code)"
    say "~/.claude/CLAUDE.md is the file again"
  fi
  echo "done: $HAL_USER's links point into $OLD again"
}

# ---------------------------------------------------------------------------------------
verify_checks() {
  local l r t
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (is the ACL on $DAVID_HOME in place?)"
  while read -r l r; do
    t=$(readlink "$HOME/$l" 2>/dev/null)
    [ "$t" = "$NEW/$r" ] || { problem "~/$l -> ${t:-(not a link)}, not $NEW/$r"; continue; }
    if [ ! -e "$t" ]; then say "~/$l is dead: $r isn't in the clone"
    elif [ ! -r "$t" ]; then problem "$t isn't readable as $ME"; fi
  done <<< "$LINKS"
  [ "$(readlink "$CLAUDE_MD" 2>/dev/null)" = "$NEW/claude/CLAUDE.md" ] || problem "~/.claude/CLAUDE.md isn't a link to $NEW/claude/CLAUDE.md"
  [ -f "$CLAUDE_KEEP" ] || problem "no $CLAUDE_KEEP"
  if [ -f "$NEW/helpers/hal_dotfiles_sync_check.sh" ] && cmp -s "$NEW/helpers/hal_dotfiles_sync_check.sh" "$CHECK"; then :
  else problem "$CHECK isn't $NEW/helpers/hal_dotfiles_sync_check.sh (run the sync-check step)"; fi
  [ -f "$CHECK_KEEP" ] || problem "no $CHECK_KEEP"
  local stray
  stray=$(stray_links)
  [ -z "$stray" ] || problem "links still into $OLD: ${stray//$'\n'/ }"
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
  if [ ! -e "$OLD" ] && [ -d "$OLD_ASIDE" ]; then echo "done already: the old clone is at $OLD_ASIDE"; exit 0; fi
  [ -d "$OLD/.git" ] || problem "no clone at $OLD"
  [ ! -e "$OLD_ASIDE" ] && [ ! -L "$OLD_ASIDE" ] || problem "$OLD_ASIDE already exists"
  verify_checks
  local since
  if [ "$(readlink "$HOME/.config/zsh/.zshrc" 2>/dev/null)" = "$NEW/zsh/zshrc" ]; then
    since=$(stat -f %Sm -t '%Y-%m-%d %H:%M %Z' "$HOME/.config/zsh/.zshrc" 2>/dev/null)
    say "the links were moved at ${since:-?} (the zshrc link's time)"
  fi
  if [ -d "$OLD/.git" ]; then
    # What the old clone holds that GitHub may not; moving it keeps all of it.
    say "in the old clone (kept as it is):"
    git -C "$OLD" --no-optional-locks status --short --branch 2>&1 | head -n 10 | sed 's/^/    /'
    git -C "$OLD" log --oneline --branches --not --remotes 2>/dev/null | head -n 10 | sed 's/^/    not on any remote: /'
    git -C "$OLD" stash list 2>/dev/null | head -n 5 | sed 's/^/    /'
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
  if [ -d "$OLD/.git" ] && [ ! -e "$OLD_ASIDE" ]; then echo "done already: the old clone is at $OLD"; exit 0; fi
  [ -d "$OLD_ASIDE/.git" ] || problem "no clone at $OLD_ASIDE"
  [ ! -e "$OLD" ] && [ ! -L "$OLD" ] || problem "$OLD already exists"
  refuse_if_problems
  say "will run: /bin/mv $OLD_ASIDE $OLD"
  dry_stop
  /bin/mv "$OLD_ASIDE" "$OLD" || die "mv failed; check that $OLD_ASIDE is still there"
  echo "done: the old clone is at $OLD again"
}

case ${1:-} in
  acl) step_acl ;;
  sync-check) step_sync_check ;;
  sync-check-rollback) step_sync_check_rollback ;;
  relink) step_relink ;;
  relink-rollback) step_relink_rollback ;;
  verify) step_verify ;;
  retire-old-clone) step_retire_old_clone ;;
  restore-old-clone) step_restore_old_clone ;;
  *) die "usage: $0 acl|sync-check|sync-check-rollback|relink|relink-rollback|verify|retire-old-clone|restore-old-clone" 2 ;;
esac
