# shellcheck shell=bash
# delete_leftover_branch: delete a local branch whose work is already on origin's default branch.
# Source this file (bash or zsh), then run it from any checkout of the repo:
#   source <dotfiles clone>/bin/lib/delete-leftover-branch.sh   # ~/Projects/Personal/dotfiles on the desk Macs
#   delete_leftover_branch <branch>
# Why each check exists: docs/agents/code-review.md, "Leftover local branch". Tests:
# ci/delete-leftover-branch-checks.sh. This file is the only copy; edit it here.

# Fails closed: every check has to succeed, a command that fails keeps the branch, and the
# delete is conditional on the tip that was checked. Local branch only; origin is never
# changed. Returns 0 after deleting, 1 when it keeps the branch.
delete_leftover_branch() {
  local b=$1 tip rh d oid rl all n o L left common names w
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
  # Every commit the branch has pointed at. Deleting the branch deletes this reflog, so a commit
  # reset off it would be lost. No reflog at all can't be checked, so it keeps the branch too.
  rl=$(git log -g --format=%H "refs/heads/$b" --) || { echo "keeping $b: couldn't read its reflog"; return 1; }
  [ -n "$rl" ] || { echo "keeping $b: it has no reflog to check"; return 1; }
  # git log -g silently skips an entry whose commit is missing, so also read each entry by
  # number (that doesn't check the object; rev-list below fails on a missing one), and make
  # sure that found at least as many entries.
  all="" n=0
  while o=$(git rev-parse -q --verify "refs/heads/${b}@{$n}"); do all="$all$o"$'\n'; n=$((n+1)); done
  L=0; while IFS= read -r o; do L=$((L+1)); done <<< "$rl"
  [ "$n" -ge "$L" ] || { echo "keeping $b: couldn't read its reflog"; return 1; }
  left=$(printf '%s' "$all" | git rev-list --stdin "^$oid") || { echo "keeping $b: couldn't check its reflog"; return 1; }
  [ -z "$left" ] || { echo "keeping $b: its reflog holds commits that aren't on origin's $d"; return 1; }
  # Worktrees last, right before the delete. update-ref -d would delete a checked-out branch,
  # or one a worktree is rebasing or bisecting (git worktree list shows those as detached).
  w=$(git worktree list --porcelain) || { echo "keeping $b: git worktree list failed"; return 1; }
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
  git config --remove-section "branch.$b" 2>/dev/null  # its upstream config, as git branch -d does
  printf 'deleted %s (was %s); to undo: git branch %q %s\n' "$b" "$tip" "$b" "$tip"
  return 0
}
# 0 when a rebase or bisect in git dir $1 names branch $2, or its state can't be read; 1 if not.
_dlb_busy() {
  local f
  for f in rebase-merge/head-name rebase-apply/head-name; do
    [ -e "$1/$f" ] || continue
    [ -r "$1/$f" ] || return 0
    [ "$(cat "$1/$f")" = "refs/heads/$2" ] && return 0
  done
  if [ -e "$1/BISECT_START" ]; then
    [ -r "$1/BISECT_START" ] || return 0
    [ "$(cat "$1/BISECT_START")" = "$2" ] && return 0
  fi
  return 1
}
