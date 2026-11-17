#!/usr/bin/env bash
#
# hal_shared_clone.sh — the on-hal steps that move `hal` onto `david`'s dotfiles clone (VIL-700
# part 2). Run by hand, one step at a time, as "One dotfiles clone on hal" in
# docs/reference/install-and-server.md says; that section has each step's command, account and
# what its exit 0 means. Step 1 runs on the Mac: helpers/hal_shared_clone_sync.sh.
#
# Each step checks the account and the state it expects, and stops before changing anything
# when the state is anything else. A step other than verify whose end state already holds
# says "done already".
# After acting, a step reads its end state back. DOTFILES_DRY_RUN=1 runs the checks and changes
# nothing.
#
# Exit 0: the step's end state holds (dry run: it holds, or the checks pass).
# 1: it doesn't; the messages say what this run changed, if anything. 2: unknown step.
#
# Overrides, for ci/hal-shared-clone-checks.sh only: HAL_SHARED_TEST_USER (stands in for
# `id -un`), HAL_SHARED_TEST_HAL_USER (the account the ACL names), HAL_SHARED_TEST_DAVID_HOME,
# HAL_SHARED_TEST_OLD_CHECK_SHA, and HERMES_HOME (as Hermes reads it).
# Messages name paths as ~/... for reading; those are never expanded.
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

# Paths in david's home closed before the ACL opens it to hal (David's decision, 2026-11-16),
# with the mode each gets. Their earlier modes go to $MODES, which acl-rollback reads.
CLOSE='.claude/file-history 700
.claude/shell-snapshots 700
scratch 700
env.sh 600'
MODES=$DAVID_HOME/.vil-700-modes-before-acl

# hal's links into its clone, as "<link under $HOME> <path in the repo>" (read on hal
# 2026-11-16). herdr/ is gone from the repo, so that link is dead in both clones; DEAD_OK names
# the repo paths allowed to be missing.
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
die() { echo "$*" >&2; exit 1; }
refuse_if_problems() { [ -z "$PROBLEMS" ] || die "Stopped before changing anything: fix the lines marked ! first."; }
need_user() { [ "$ME" = "$1" ] || die "run this step as \`$1\` (this is \`$ME\`); nothing changed"; }
done_already() { echo "done already: $*"; exit 0; }
dry_stop() { [ "$DRY" = 1 ] || return 0; echo "[dry-run] nothing changed."; exit 0; }
dead_ok() { case $DEAD_OK in *" $1 "*) return 0 ;; esac; return 1; }
mode_of() { stat -f %Lp "$1"; }
sha_of() { local s; s=$(shasum -a 256 < "$1") || return 1; echo "${s%% *}"; }

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

# ---------------------------------------------------------------------------------------
# acl_entries: the ACL entries of $HOME that name hal, one per line; fails when ls does.
acl_entries() {
  local out
  out=$(/bin/ls -led "$HOME") || return 1
  printf '%s\n' "$out" | awk -v u="user:$HAL_USER" '$2 == u { $1 = ""; sub(/^ /, ""); print }'
}
# allows <path>: an ACL entry on the path allows something (true when its ACL can't be read).
allows() {
  local out
  out=$(/bin/ls -led "$1") || return 0
  printf '%s\n' "$out" | awk 'NR > 1 && / allow / { f = 1 } END { exit !f }'
}
# closed <path> <mode>: only the owner gets in: not a link, mode <mode>, no ACL entry allowing anything.
closed() { [ ! -L "$1" ] && [ "$(mode_of "$1" 2>/dev/null)" = "$2" ] && ! allows "$1"; }
recorded_mode() { [ -f "$MODES" ] && awk -v p="$1" '$1 == p { print $2; exit }' "$MODES"; }
# acl_done: each of the four paths that exists is closed, and hal's only entry on $HOME is $ACE.
acl_done() {
  local p want e
  while read -r p want; do
    [ -e "$HOME/$p" ] || [ -L "$HOME/$p" ] || continue
    closed "$HOME/$p" "$want" || return 1
  done <<< "$CLOSE"
  e=$(acl_entries) && [ "$e" = "$ACE" ]
}

step_acl() {
  need_user david
  echo "acl: close four paths in $HOME, then let \`$HAL_USER\` search $HOME, so it can read $NEW"
  acl_done && done_already "each of the four paths is closed or missing, and $HOME has \"$ACE\""
  id -u "$HAL_USER" >/dev/null 2>&1 || problem "no account named $HAL_USER"
  [ -d "$NEW/.git" ] || problem "no clone at $NEW"
  # hal reads the clone through the group bits (hal is in david's group, staff) or the other
  # bits, so the clone must be open to both; the ACL only opens $HOME itself.
  local x bad p want cur todo='' entries open
  for x in "$DAVID_HOME/Projects" "$DAVID_HOME/Projects/Personal"; do
    [ -n "$(find -H "$x" -maxdepth 0 -perm -011 2>/dev/null)" ] || problem "$x isn't searchable by group and other"
  done
  if [ -d "$NEW/.git" ]; then
    if bad=$(find "$NEW" -path "$NEW/.git/objects" -prune -o \( -type d ! -perm -055 -o -type f ! -perm -044 \) -print); then
      bad=$(printf '%s\n' "$bad" | awk 'NF && NR <= 10')
      [ -z "$bad" ] || problem "group or other can't read these in the clone (first 10): ${bad//$'\n'/ }"
    else
      problem "couldn't check every file in $NEW (find failed)"
    fi
  fi
  while read -r p want; do
    x=$HOME/$p
    if [ -L "$x" ]; then problem "~/$p is a link; closing it would change what it points at"
    elif [ ! -e "$x" ]; then say "~/$p doesn't exist; skipped"
    elif allows "$x"; then problem "~/$p has an ACL entry that allows access (see ls -led ~/$p); this step doesn't remove entries it didn't add"
    elif ! cur=$(mode_of "$x"); then problem "can't read the mode of ~/$p"
    elif [ "$cur" = "$want" ]; then say "~/$p is already $want"
    else todo="$todo$p $want $cur"$'\n'; say "will close ~/$p: $cur -> $want (its mode now goes to $MODES)"
    fi
  done <<< "$CLOSE"
  entries=$(acl_entries) || problem "couldn't read the ACL of $HOME"
  [ -z "$entries" ] || [ "$entries" = "$ACE" ] || problem "$HOME already has another entry for $HAL_USER: $entries"
  if [ "$entries" = "$ACE" ] && [ -n "$PROBLEMS" ]; then
    say "note: $HOME has \"$ACE\" from an earlier run; it stays while this step is stopped"
  fi
  if open=$(find "$HOME" -mindepth 1 -maxdepth 1 \( -perm -001 -o -perm -004 -o -perm -010 -o -perm -040 \)); then
    say "by group and other mode bits alone (ACL entries not checked), $HAL_USER can read these at the top of $HOME (the four paths left out):"
    printf '%s\n' "$open" | sed "s|^$HOME/||" | sort | while IFS= read -r x; do
      printf '%s\n' "$CLOSE" | awk -v p="$x" '$1 == p { f = 1 } END { exit f }' && echo "    ~/$x"
    done
  else
    problem "couldn't list what's open in $HOME"
  fi
  refuse_if_problems
  [ "$entries" = "$ACE" ] || say "will run: /bin/chmod +a \"$ACE\" $HOME"
  dry_stop
  # Record each earlier mode before changing it (a record already there is kept: it's the
  # mode from before the first run). If any path isn't closed, the entry isn't added.
  local failed=''
  while read -r p want cur; do
    [ -n "$p" ] || continue
    if [ -z "$(recorded_mode "$p")" ] && ! ( umask 077; printf '%s %s\n' "$p" "$cur" >> "$MODES" ); then
      failed="$failed ~/$p (its mode couldn't be recorded, so it wasn't changed)"; continue
    fi
    if /bin/chmod "$want" "$HOME/$p" && closed "$HOME/$p" "$want"; then say "~/$p: closed to $want"; else failed="$failed ~/$p"; fi
  done <<< "$todo"
  if [ -n "$failed" ]; then
    [ "$entries" != "$ACE" ] ||
      die "couldn't close:$failed. $HOME still has \"$ACE\" from an earlier run, so $HAL_USER may reach them: close them by hand, or run relink-rollback (as $HAL_USER), then acl-rollback."
    die "couldn't close:$failed. The entry wasn't added. Fix that and run the acl step again; acl-rollback reopens what this run closed."
  fi
  if [ "$entries" != "$ACE" ]; then
    /bin/chmod +a "$ACE" "$HOME" || die "chmod +a failed: the four paths are closed or missing, the entry wasn't added. Run the acl step again."
  fi
  acl_done || die "the four paths or $HOME's entries for $HAL_USER don't read back as expected; look at ls -led ~ and run the acl step again"
  echo "done: the four paths are closed or missing, and $HOME has \"$ACE\". Next, as $HAL_USER: the sync-check step."
}

step_acl_rollback() {
  need_user david
  echo "acl-rollback: take \"$ACE\" off $HOME, then reopen the paths the acl step closed"
  say "run it only after relink-rollback: while $HAL_USER's links point into $NEW, removing the entry breaks $HAL_USER's shell and git"
  local entries p want rec x todo='' failed=''
  entries=$(acl_entries) || problem "couldn't read the ACL of $HOME"
  [ -z "$entries" ] || [ "$entries" = "$ACE" ] || problem "$HOME has another entry for $HAL_USER: $entries"
  [ -f "$MODES" ] || say "no $MODES, so no recorded mode to put back; the four paths stay as they are"
  while read -r p want; do
    x=$HOME/$p
    rec=$(recorded_mode "$p")
    [ -n "$rec" ] || continue
    if [ -L "$x" ] || [ ! -e "$x" ]; then say "~/$p is missing or a link; left as it is"
    elif [ "$(mode_of "$x")" = "$want" ]; then todo="$todo$p $rec"$'\n'; say "will reopen ~/$p: $want -> $rec"
    else say "~/$p isn't at the closed $want; left as it is"
    fi
  done <<< "$CLOSE"
  refuse_if_problems
  [ -n "$entries" ] || [ -n "$todo" ] || done_already "no entry for $HAL_USER on $HOME, and no path with a recorded mode is at its closed mode"
  [ -z "$entries" ] || say "will run: /bin/chmod -a \"$ACE\" $HOME"
  dry_stop
  if [ -n "$entries" ]; then /bin/chmod -a "$ACE" "$HOME" || die "chmod -a failed; nothing changed"; say "took \"$ACE\" off $HOME"; fi
  while read -r p rec; do
    [ -n "$p" ] || continue
    if /bin/chmod "$rec" "$HOME/$p" && [ "$(mode_of "$HOME/$p")" = "$rec" ]; then say "~/$p: back to $rec"; else failed="$failed ~/$p"; fi
  done <<< "$todo"
  entries=$(acl_entries) && [ -z "$entries" ] || die "$HOME still shows an entry for $HAL_USER (${entries:-unreadable}); look at ls -led ~ and run acl-rollback again"
  [ -z "$failed" ] || die "no entry for $HAL_USER on $HOME now, but these didn't go back to their recorded mode:$failed. Run acl-rollback again once that's fixed."
  echo "done: no entry for $HAL_USER on $HOME, and each path with a recorded mode that was at its closed mode is back at it ($MODES is kept)"
}

# ---------------------------------------------------------------------------------------
keep_is_original() { [ -f "$CHECK_KEEP" ] && [ ! -L "$CHECK_KEEP" ] && [ "$(sha_of "$CHECK_KEEP")" = "$CHECK_OLD_SHA" ]; }
# installed_check_ok: the installed check is an executable regular file with the shared
# clone's content, and the original is kept as $CHECK_KEEP.
installed_check_ok() {
  [ ! -L "$CHECK" ] && [ -f "$CHECK" ] && [ -x "$CHECK" ] && [ -f "$CHECK_SRC" ] && cmp -s "$CHECK_SRC" "$CHECK" && keep_is_original
}
original_active() { [ ! -L "$CHECK" ] && [ -f "$CHECK" ] && [ "$(sha_of "$CHECK")" = "$CHECK_OLD_SHA" ]; }
# put <file> <mode>: copy it over $CHECK through a temp file and a rename. On failure the
# active script is unchanged, and a temp file that can't be removed is named.
put() {
  local tmp=$CHECK.vil700-tmp.$$
  /bin/cp "$1" "$tmp" && /bin/chmod "$2" "$tmp" && cmp -s "$1" "$tmp" && /bin/mv -f "$tmp" "$CHECK" && return 0
  /bin/rm -f "$tmp"; [ ! -e "$tmp" ] || echo "couldn't remove the temp file $tmp; remove it by hand" >&2
  return 1
}

step_sync_check() {
  need_user "$HAL_USER"
  echo "sync-check: install $CHECK_SRC as $CHECK"
  installed_check_ok && done_already "$CHECK is an executable copy of $CHECK_SRC, and the original is $CHECK_KEEP"
  [ -r "$CHECK_SRC" ] || problem "can't read $CHECK_SRC as $ME (run the acl step as david first)"
  local keep=0
  if [ -L "$CHECK" ] || [ ! -f "$CHECK" ]; then problem "$CHECK is missing or not a regular file"
  elif keep_is_original; then
    # An earlier run kept the original, so what's installed must be this repo's check (any
    # version, by its header) or that original.
    awk -v m="$CHECK_MARK" 'NR <= 5 && index($0, m) == 1 { f = 1 } END { exit !f }' "$CHECK" || cmp -s "$CHECK" "$CHECK_KEEP" ||
      problem "$CHECK is neither this repo's check nor the original kept in $CHECK_KEEP"
  elif [ -e "$CHECK_KEEP" ] || [ -L "$CHECK_KEEP" ]; then problem "$CHECK_KEEP exists and isn't the original check"
  elif ! original_active; then problem "$CHECK isn't the original check (sha256 differs); compare it with $CHECK_SRC by hand"
  else keep=1; say "will keep the current script as $CHECK_KEEP"
  fi
  refuse_if_problems
  say "will copy $CHECK_SRC over $CHECK (a temp file, then a rename)"
  dry_stop
  if [ "$keep" = 1 ]; then
    # A hard link keeps the original file as it is, and fails if the name is taken.
    /bin/ln "$CHECK" "$CHECK_KEEP" || die "couldn't keep $CHECK as $CHECK_KEEP; nothing changed"
    say "kept the original as $CHECK_KEEP (a second name for the same file)"
  fi
  put "$CHECK_SRC" 755 || die "couldn't install $CHECK; the active script is unchanged. Run the sync-check step again."
  installed_check_ok || die "installed, but $CHECK doesn't read back as an executable copy of $CHECK_SRC; run the sync-check step again"
  echo "done: $CHECK is the new check; the original is $CHECK_KEEP. Next: the relink step."
}

step_sync_check_rollback() {
  need_user "$HAL_USER"
  echo "sync-check-rollback: put $CHECK_KEEP back as $CHECK"
  original_active && done_already "$CHECK is the original check"
  keep_is_original || problem "no $CHECK_KEEP holding the original check"
  # The original runs git in the clone the zshrc link points at, which only works in hal's own.
  case $(readlink "$HOME/.config/zsh/.zshrc" 2>/dev/null) in
    "$OLD"/*) ;;
    *) problem "~/.config/zsh/.zshrc doesn't point into $OLD, where the original check works; run relink-rollback first" ;;
  esac
  refuse_if_problems
  say "will copy $CHECK_KEEP over $CHECK ($CHECK_KEEP stays)"
  dry_stop
  put "$CHECK_KEEP" "$(mode_of "$CHECK_KEEP")" || die "couldn't restore $CHECK; the active script is unchanged. Run sync-check-rollback again."
  original_active || die "restored, but $CHECK doesn't read back as the original; run sync-check-rollback again"
  echo "done: $CHECK is the original again"
}

# ---------------------------------------------------------------------------------------
# plan_forward / plan_back: check each expected link and set TODO to the ones to move, as
# "<link> <new target>" lines. Problems go to problem().
plan_forward() {
  local l r t
  TODO=''
  while read -r l r; do
    t=$(readlink "$HOME/$l") || { problem "~/$l isn't a link"; continue; }
    case $t in "$OLD/$r"|"$NEW/$r") ;; *) problem "~/$l points at $t, not $OLD/$r or $NEW/$r"; continue ;; esac
    if [ ! -r "$NEW/$r" ] && ! { dead_ok "$r" && [ ! -e "$NEW/$r" ]; }; then problem "$NEW/$r is missing or unreadable as $ME"; continue; fi
    [ "$t" = "$NEW/$r" ] || TODO="$TODO$l $NEW/$r"$'\n'
  done <<< "$LINKS"
}
# Going back never compares the clones: after a pull as david they differ, and that's when a
# rollback may be wanted.
plan_back() {
  local l r t
  TODO=''
  while read -r l r; do
    t=$(readlink "$HOME/$l") || { problem "~/$l isn't a link"; continue; }
    case $t in
      "$OLD/$r") ;;
      "$NEW/$r") if [ -e "$OLD/$r" ] || dead_ok "$r"; then TODO="$TODO$l $OLD/$r"$'\n'; else problem "$OLD/$r is missing"; fi ;;
      *) problem "~/$l points at $t, not $NEW/$r or $OLD/$r" ;;
    esac
  done <<< "$LINKS"
}

# move_links: re-point each TODO link by renaming a new link over it (atomic per link).
MOVED=0
move_links() {
  local l t tmp
  while read -r l t; do
    [ -n "$l" ] || continue
    tmp=$HOME/$l.vil700-tmp.$$
    if ! { /bin/ln -s "$t" "$tmp" && /bin/mv -fh "$tmp" "$HOME/$l"; }; then
      /bin/rm -f "$tmp"; [ ! -L "$tmp" ] || echo "couldn't remove the temp link $tmp; remove it by hand" >&2
      echo "failed at ~/$l, after moving $MOVED link(s) on this run" >&2
      return 1
    fi
    MOVED=$((MOVED + 1)); say "~/$l -> $t"
  done <<< "$TODO"
}

# links_into <clone>: every expected link points at its file in that clone.
links_into() {
  local l r
  while read -r l r; do [ "$(readlink "$HOME/$l" 2>/dev/null)" = "$1/$r" ] || return 1; done <<< "$LINKS"
}
# all_moved: relink's end state.
all_moved() {
  links_into "$NEW" && [ "$(readlink "$CLAUDE_MD" 2>/dev/null)" = "$NEW/claude/CLAUDE.md" ] && [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ]
}
# all_back: relink-rollback's end state.
all_back() { links_into "$OLD" && [ -f "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; }

step_relink() {
  need_user "$HAL_USER"
  echo "relink: point $HAL_USER's links from $OLD to $NEW, and link ~/.claude/CLAUDE.md"
  all_moved && done_already "all 24 links and ~/.claude/CLAUDE.md point into $NEW, and the old CLAUDE.md is kept"
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (run the acl step as david first)"
  [ -d "$OLD" ] || problem "no $OLD (if it was moved aside, run restore-old-clone first)"
  refuse_if_problems
  local ho hn claude=0
  ho=$(head_of "$OLD") hn=$(head_of "$NEW")
  [ -n "$ho" ] && [ "$ho" = "$hn" ] || problem "the clones aren't on one commit ($OLD: ${ho:-?}, $NEW: ${hn:-?}); run step 1 on the Mac first"
  installed_check_ok || problem "the installed check isn't step 3's; run the sync-check step first"
  plan_forward
  # CLAUDE.md: the file is kept (a hard link) and the name becomes a link. A second name for
  # the same file is an earlier run that stopped between those two.
  if [ -L "$CLAUDE_MD" ]; then
    { [ "$(readlink "$CLAUDE_MD")" = "$NEW/claude/CLAUDE.md" ] && [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ]; } ||
      problem "~/.claude/CLAUDE.md is a link to $(readlink "$CLAUDE_MD"), or $CLAUDE_KEEP is missing"
  elif [ ! -f "$CLAUDE_MD" ]; then problem "~/.claude/CLAUDE.md is missing"
  elif { [ -e "$CLAUDE_KEEP" ] || [ -L "$CLAUDE_KEEP" ]; } && ! [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ]; then
    problem "$CLAUDE_KEEP already exists, and isn't ~/.claude/CLAUDE.md"
  elif [ ! -r "$NEW/claude/CLAUDE.md" ]; then problem "$NEW/claude/CLAUDE.md isn't readable as $ME"
  else claude=1; say "will keep ~/.claude/CLAUDE.md as $CLAUDE_KEEP and link the name to $NEW/claude/CLAUDE.md"
  fi
  refuse_if_problems
  say "will move $(printf '%s' "$TODO" | grep -c .) link(s) into $NEW"
  if [ "$DRY" = 1 ]; then printf '%s' "$TODO" | sed 's/^/    ~\//; s/ / -> /'; fi
  dry_stop
  move_links || die "Run relink again to finish, or relink-rollback to undo."
  if [ "$claude" = 1 ]; then
    local tmp=$CLAUDE_MD.vil700-tmp.$$
    [ "$CLAUDE_MD" -ef "$CLAUDE_KEEP" ] || /bin/ln "$CLAUDE_MD" "$CLAUDE_KEEP" ||
      die "couldn't keep ~/.claude/CLAUDE.md as $CLAUDE_KEEP; it is unchanged ($MOVED link(s) moved on this run). Run relink again, or relink-rollback."
    if ! { /bin/ln -s "$NEW/claude/CLAUDE.md" "$tmp" && /bin/mv -f "$tmp" "$CLAUDE_MD"; }; then
      /bin/rm -f "$tmp"; [ ! -L "$tmp" ] || echo "couldn't remove the temp link $tmp; remove it by hand" >&2
      die "~/.claude/CLAUDE.md is unchanged, and $CLAUDE_KEEP is a second name for it ($MOVED link(s) moved on this run). Run relink again, or relink-rollback."
    fi
    say "~/.claude/CLAUDE.md -> $NEW/claude/CLAUDE.md (the file is kept as $CLAUDE_KEEP)"
  fi
  all_moved || die "the links don't all read back as pointing into $NEW; run relink again"
  echo "done: $HAL_USER's links and ~/.claude/CLAUDE.md point into $NEW. Next: the verify step."
}

step_relink_rollback() {
  need_user "$HAL_USER"
  echo "relink-rollback: point $HAL_USER's links back into $OLD, and restore ~/.claude/CLAUDE.md"
  all_back && done_already "the 24 links point into $OLD, and ~/.claude/CLAUDE.md is a file"
  [ -d "$OLD" ] || { problem "no $OLD; if it was moved aside, run restore-old-clone first"; refuse_if_problems; }
  plan_back
  local claude=0
  if [ -L "$CLAUDE_MD" ]; then
    if [ "$(readlink "$CLAUDE_MD")" = "$NEW/claude/CLAUDE.md" ] && [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ]; then
      claude=1; say "will put $CLAUDE_KEEP back as ~/.claude/CLAUDE.md"
    else problem "~/.claude/CLAUDE.md is a link, but not relink's with $CLAUDE_KEEP beside it"; fi
  elif [ ! -f "$CLAUDE_MD" ]; then problem "~/.claude/CLAUDE.md is missing"
  fi
  refuse_if_problems
  say "will move $(printf '%s' "$TODO" | grep -c .) link(s) back into $OLD"
  dry_stop
  move_links || die "Run relink-rollback again to finish."
  if [ "$claude" = 1 ]; then
    /bin/mv -f "$CLAUDE_KEEP" "$CLAUDE_MD" ||
      die "~/.claude/CLAUDE.md is still the link, and $CLAUDE_KEEP holds the file ($MOVED link(s) moved back on this run). Run relink-rollback again."
    say "~/.claude/CLAUDE.md is the file again"
  fi
  all_back || die "the links don't all read back as pointing into $OLD; run relink-rollback again"
  echo "done: $HAL_USER's links point into $OLD again, and ~/.claude/CLAUDE.md is the file"
}

# ---------------------------------------------------------------------------------------
# stray_links: sets STRAY to the symlinks in $HOME, outside the expected list, whose target
# text starts with hal's own clone's path; fails when the scan can't read what it walks. macOS
# closes Library, Desktop, Documents, Downloads, Movies, Music and Pictures to ssh sessions,
# so those, .Trash and the clone itself are skipped.
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

# verify_checks: verify's checks, as problem() lines.
verify_checks() {
  local l r t
  [ -r "$NEW/.git/HEAD" ] || problem "can't read $NEW as $ME (is the ACL on $DAVID_HOME in place?)"
  while read -r l r; do
    t=$(readlink "$HOME/$l" 2>/dev/null)
    if [ "$t" != "$NEW/$r" ]; then problem "~/$l -> ${t:-(not a link)}, not $NEW/$r"
    elif [ ! -r "$t" ] && ! { dead_ok "$r" && [ ! -e "$t" ]; }; then problem "$t is missing or unreadable as $ME"
    fi
  done <<< "$LINKS"
  if [ "$(readlink "$CLAUDE_MD" 2>/dev/null)" != "$NEW/claude/CLAUDE.md" ]; then problem "~/.claude/CLAUDE.md isn't a link to $NEW/claude/CLAUDE.md"
  elif [ ! -r "$NEW/claude/CLAUDE.md" ]; then problem "$NEW/claude/CLAUDE.md is missing or unreadable as $ME"; fi
  [ -f "$CLAUDE_KEEP" ] && [ ! -L "$CLAUDE_KEEP" ] || problem "no $CLAUDE_KEEP file"
  if ! stray_links; then problem "couldn't scan all of $HOME for links into $OLD"
  elif [ -n "$STRAY" ]; then problem "links still into $OLD: $STRAY"; fi
  installed_check_ok || problem "$CHECK isn't an executable copy of $CHECK_SRC with the original kept as $CHECK_KEEP (run the sync-check step)"
}

step_verify() {
  need_user "$HAL_USER"
  echo "verify: check that $HAL_USER's links point into $NEW"
  verify_checks
  [ -z "$PROBLEMS" ] || die "not as expected; see the lines marked !"
  echo "ok: the 24 links and ~/.claude/CLAUDE.md point into $NEW, the scan found no other symlink to $OLD or a path inside it, and the new sync-check is installed"
}

# ---------------------------------------------------------------------------------------
retired() { [ ! -e "$OLD" ] && [ ! -L "$OLD" ] && [ -d "$OLD_ASIDE/.git" ]; }
restored() { [ -d "$OLD/.git" ] && [ ! -e "$OLD_ASIDE" ] && [ ! -L "$OLD_ASIDE" ]; }

step_retire_old_clone() {
  need_user "$HAL_USER"
  echo "retire-old-clone: move $OLD aside to $OLD_ASIDE (nothing is deleted)"
  retired && done_already "the old clone is at $OLD_ASIDE"
  verify_checks
  [ -d "$OLD/.git" ] || problem "no clone at $OLD"
  [ ! -e "$OLD_ASIDE" ] && [ ! -L "$OLD_ASIDE" ] || problem "$OLD_ASIDE already exists"
  refuse_if_problems
  say "will run: /bin/mv $OLD $OLD_ASIDE"
  dry_stop
  /bin/mv "$OLD" "$OLD_ASIDE"
  retired || die "the move failed or didn't finish; look at $OLD and $OLD_ASIDE"
  echo "done: the old clone is at $OLD_ASIDE. To undo: the restore-old-clone step."
}

step_restore_old_clone() {
  need_user "$HAL_USER"
  echo "restore-old-clone: move $OLD_ASIDE back to $OLD"
  restored && done_already "the old clone is at $OLD"
  [ -d "$OLD_ASIDE/.git" ] || problem "no clone at $OLD_ASIDE"
  [ ! -e "$OLD" ] && [ ! -L "$OLD" ] || problem "$OLD already exists"
  refuse_if_problems
  say "will run: /bin/mv $OLD_ASIDE $OLD"
  dry_stop
  /bin/mv "$OLD_ASIDE" "$OLD"
  restored || die "the move failed or didn't finish; look at $OLD_ASIDE and $OLD"
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
  *) echo "usage: $0 acl|acl-rollback|sync-check|sync-check-rollback|relink|relink-rollback|verify|retire-old-clone|restore-old-clone" >&2; exit 2 ;;
esac
