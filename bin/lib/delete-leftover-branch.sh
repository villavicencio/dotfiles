# shellcheck shell=bash
# delete_leftover_branch: delete a local branch whose work is already on origin's default branch.
# Source this file (bash or zsh), then run it from any checkout of the repo:
#   source <dotfiles clone>/bin/lib/delete-leftover-branch.sh   # ~/Projects/Personal/dotfiles on the desk Macs
#   delete_leftover_branch <branch>
# Why each check exists: docs/agents/code-review.md, "Leftover local branch". Tests:
# ci/delete-leftover-branch-checks.sh. This file is the only copy; edit it here.

# Fails closed: every check has to succeed, a command that fails keeps the branch, and the
# delete is conditional on the tip that was checked. Local branch only; origin is never
# changed. Returns 0 after deleting, 1 when it keeps the branch, 2 when it deleted the branch
# but couldn't remove (or check) its config section.
delete_leftover_branch() {
  local b=$1 tip rh d oid fmt lf rl line o x all left common names w rc
  [ -n "$b" ] || { echo "keeping: no branch named"; return 1; }
  git check-ref-format "refs/heads/$b" || { echo "keeping $b: not a valid branch name"; return 1; }
  tip=$(git rev-parse -q --verify "refs/heads/${b}^{commit}") && [ -n "$tip" ] \
    || { echo "keeping $b: no such local branch"; return 1; }
  # origin's default branch and its tip, asked of origin itself: a cached origin/HEAD can name
  # an old default branch, and a narrow fetch refspec can leave origin/<default> missing or old.
  rh=$(git ls-remote --symref origin HEAD) || { echo "keeping $b: couldn't ask origin for its default branch"; return 1; }
  d=$(printf '%s\n' "$rh" | awk '$1=="ref:" && $3=="HEAD" && $2 ~ /^refs\/heads\// {sub(/^refs\/heads\//,"",$2); print $2; exit}')
  oid=$(printf '%s\n' "$rh" | awk '$1!="ref:" && $2=="HEAD" {print $1; exit}')
  [ -n "$d" ] || { echo "keeping $b: origin didn't name a default branch"; return 1; }
  case $oid in ''|*[!0-9a-f]*) echo "keeping $b: origin didn't give its default branch's commit"; return 1 ;; esac
  [ "${#oid}" = 40 ] || [ "${#oid}" = 64 ] || { echo "keeping $b: origin didn't give its default branch's commit"; return 1; }
  [ "$b" != "$d" ] || { echo "keeping $b: it is origin's default branch"; return 1; }
  # That commit has to be here to compare against. Explicit refspec: works with a narrow one.
  git cat-file -e "${oid}^{commit}" 2>/dev/null \
    || { git fetch -q origin "+refs/heads/${d}:refs/remotes/origin/${d}" && git cat-file -e "${oid}^{commit}"; } \
    || { echo "keeping $b: couldn't fetch origin's $d"; return 1; }
  git merge-base --is-ancestor "$tip" "$oid" \
    || { echo "keeping $b: its tip isn't on origin's $d (or the check failed)"; return 1; }
  # Every commit the branch's reflog names, on both sides of each entry. Deleting the branch
  # deletes its reflog, so a commit reset off it would be lost. The raw file is read because
  # `git log -g` and <branch>@{n} give only each entry's new side, which misses the old side of
  # the oldest entry (a commit from before logging began, or from expired entries), and
  # `git log -g` skips an entry whose commit is missing. No reflog can't be checked: keep.
  # The raw file is the reflog only when refs are stored as files. git before 2.45 has no
  # --show-ref-format (rev-parse echoes the unknown flag back), so there it keeps the branch.
  fmt=$(git rev-parse --show-ref-format) || { echo "keeping $b: couldn't tell how refs are stored here"; return 1; }
  [ "$fmt" = files ] || { echo "keeping $b: refs here aren't stored as files (${fmt:-no answer}), so its reflog can't be read"; return 1; }
  lf=$(git rev-parse --git-path "logs/refs/heads/$b") || { echo "keeping $b: couldn't find its reflog"; return 1; }
  [ -e "$lf" ] || { echo "keeping $b: it has no reflog to check"; return 1; }
  rl=$(cat "$lf") || { echo "keeping $b: couldn't read its reflog"; return 1; }
  all=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $line in *" "*) ;; *) echo "keeping $b: its reflog has a line it can't read"; return 1 ;; esac
    o=${line%% *}; line=${line#* }
    for x in "$o" "${line%% *}"; do
      case $x in ''|*[!0-9a-f]*) echo "keeping $b: its reflog has a line it can't read"; return 1 ;; esac
      [ "${#x}" = "${#oid}" ] || { echo "keeping $b: its reflog has a line it can't read"; return 1; }
      case $x in *[!0]*) all="$all$x"$'\n' ;; esac  # all zeros: the side before the branch existed
    done
  done <<< "$rl"
  [ -n "$all" ] || { echo "keeping $b: it has no reflog to check"; return 1; }
  left=$(printf '%s' "$all" | git rev-list --stdin "^$oid") || { echo "keeping $b: couldn't check its reflog"; return 1; }
  [ -z "$left" ] || { echo "keeping $b: its reflog holds commits that aren't on origin's $d"; return 1; }
  # Worktrees last, right before the delete. update-ref -d would delete a checked-out branch,
  # or one a worktree is rebasing or bisecting (git worktree list shows those as detached).
  w=$(git worktree list --porcelain) || { echo "keeping $b: git worktree list failed"; return 1; }
  [ -n "$w" ] || { echo "keeping $b: git worktree list gave nothing"; return 1; }  # it always lists the main one
  printf '%s\n' "$w" | grep -qxF "branch refs/heads/$b"
  case $? in
    0) echo "keeping $b: a worktree has it checked out"; return 1 ;;
    1) ;;
    *) echo "keeping $b: couldn't read the worktree list"; return 1 ;;
  esac
  common=$(git rev-parse --path-format=absolute --git-common-dir) && [ -d "$common" ] \
    || { echo "keeping $b: couldn't find the repository's git dir"; return 1; }
  _dlb_busy "$common" "$b" && { echo "keeping $b: a rebase or bisect in progress names it"; return 1; }
  if [ -d "$common/worktrees" ]; then
    names=$(ls -A "$common/worktrees") || { echo "keeping $b: couldn't list worktrees"; return 1; }
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      _dlb_busy "$common/worktrees/$w" "$b" && { echo "keeping $b: a rebase or bisect in progress names it"; return 1; }
    done <<< "$names"
  fi
  git update-ref -d "refs/heads/$b" "$tip" || { echo "keeping $b: it moved since the check, or the delete failed"; return 1; }
  printf 'deleted %s (was %s); to undo: git branch %q %s\n' "$b" "$tip" "$b" "$tip"
  # Its config section (upstream and the like), as git branch -d removes it. The branch is gone
  # either way, so a failure here returns 2, not "keeping": say so, or a branch recreated with
  # this name inherits the old settings. Exit 1 from --get-regexp means no branch config at all.
  names=$(git config --local --name-only --get-regexp '^branch\.'); rc=$?
  [ "$rc" -le 1 ] || { printf 'config check failed: branch.%s may still be in git config; remove it with: git config --local --remove-section %q\n' "$b" "branch.$b"; return 2; }
  while IFS= read -r line; do
    [ "${line%.*}" = "branch.$b" ] || continue
    git config --local --remove-section "branch.$b" && return 0
    printf 'config removal failed: branch.%s is still in git config; remove it with: git config --local --remove-section %q\n' "$b" "branch.$b"
    return 2
  done <<< "$names"
  return 0
}
# 0 when a rebase or bisect in git dir $1 names branch $2, or its state can't be read; 1 if not.
_dlb_busy() {
  local f c
  # A git dir it can't look inside would make the -e tests below read as "no rebase": busy.
  [ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ] || return 0
  for f in rebase-merge/head-name rebase-apply/head-name; do
    [ -e "$1/$f" ] || continue
    c=$(cat "$1/$f") || return 0
    [ "$c" = "refs/heads/$2" ] && return 0
  done
  if [ -e "$1/BISECT_START" ]; then
    c=$(cat "$1/BISECT_START") || return 0
    [ "$c" = "$2" ] && return 0
  fi
  return 1
}
