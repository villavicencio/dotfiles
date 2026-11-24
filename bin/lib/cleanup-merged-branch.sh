# shellcheck shell=bash
# cleanup_merged_branch: delete a merged PR's branch locally and on origin.
# Source this file (bash or zsh), then run it from any worktree of the repo:
#   source <dotfiles clone>/bin/lib/cleanup-merged-branch.sh   # ~/Projects/Personal/dotfiles on the desk Macs
#   cleanup_merged_branch <pr> <default branch>
# Run from inside the linked worktree it removes, it moves the shell to the main worktree.
# Why each check exists: docs/agents/code-review.md, "After the merge". bin/wt's
# `wt done` calls it too. This file is the only copy; edit it here.

# Delete a merged PR's branch locally and on origin. Usage: cleanup_merged_branch <pr> <base>
# Fails closed: every check runs before anything changes (including that each worktree step
# can succeed), every failure returns 1, and the step that can delete files (removing a
# worktree) runs only after origin accepted the delete.
cleanup_merged_branch() {
  local N=$1 base=$2 b oid cross tip cherry merges wl main wts w s rc sw rl gd deleted=0 dets="" detached=""
  read -r b oid cross < <(gh pr view "$N" --json state,headRefName,headRefOid,isCrossRepository \
    -q 'select(.state=="MERGED") | "\(.headRefName) \(.headRefOid) \(.isCrossRepository)"')
  [ -n "$oid" ] || { echo "PR $N is not merged (or gh failed): stop"; return 1; }
  [ "$cross" = false ] || { echo "PR $N's head is in a fork: no branch of ours to delete"; return 1; }
  # Local tip: absent, the merged head, or a stale copy of it (the PR was rebased or updated
  # on GitHub). A stale copy has no commit that isn't patch-equivalent to one in the merged
  # head (`git cherry` marks those `-`). Any `+` commit is new work: keep the branch.
  tip=$(git rev-parse -q --verify "refs/heads/$b")
  if [ -n "$tip" ] && [ "$tip" != "$oid" ]; then
    git cat-file -e "$oid^{commit}" 2>/dev/null || git fetch -q origin "refs/pull/$N/head" \
      || { echo "can't fetch PR $N's merged head: stop"; return 1; }
    cherry=$(git cherry "$oid" "$tip") || { echo "git cherry failed: stop"; return 1; }
    case $cherry in *+*) echo "$b has commits that aren't in PR $N: keeping it"; return 1 ;; esac
    # git cherry skips merge commits, and one can carry its own conflict resolution.
    merges=$(git rev-list --merges "$oid..$tip") || return 1
    [ -z "$merges" ] || { echo "$b has a merge commit that isn't in PR $N: keeping it"; return 1; }
  fi
  # Worktrees on $b: all clean before anything changes. A linked one will be removed, which
  # deletes ignored files too (.env, build output), so for those ignored files count as dirty.
  wl=$(git worktree list --porcelain) || { echo "git worktree list failed: stop"; return 1; }
  main=$(printf '%s\n' "$wl" | awk '/^worktree /{print substr($0,10); exit}')
  # The shell's own directory may be a worktree this run removes, so from that step on each git
  # call names its directory with -C: the worktree it acts on, or the main worktree, which is
  # never removed. Check now that git runs there.
  if [ -z "$main" ] || ! git -C "$main" rev-parse --git-dir >/dev/null 2>&1; then
    echo "can't run git in the main worktree ${main:-?}: stop"; return 1
  fi
  wts=$(printf '%s\n' "$wl" | awk -v r="branch refs/heads/$b" '/^worktree /{w=substr($0,10)} $0==r{print w}')
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    if [ "$w" = "$main" ]; then s=$(git -C "$w" status --porcelain) || return 1
    else
      # `git worktree remove` refuses a locked worktree and one with submodules.
      printf '%s\n' "$wl" | awk -v t="$w" '/^worktree /{c=(substr($0,10)==t)} c && /^locked/{f=1} END{exit !f}' \
        && { echo "$w is locked: keeping $b"; return 1; }
      gd=$(git -C "$w" rev-parse --absolute-git-dir) || return 1
      if [ -e "$gd/modules" ]; then
        # Every Orca worktree has one (dotbot). Detach it instead: that deletes nothing, so
        # ignored files don't count, and it's left for Force delete in Orca.
        s=$(git -C "$w" status --porcelain) || return 1
        dets="$dets$w"$'\n'
      else s=$(git -C "$w" status --porcelain --ignored) || return 1
      fi
    fi
    [ -z "$s" ] || { echo "$w has changes, untracked or ignored files: keeping $b"; return 1; }
  done < <(printf '%s\n' "$wts")
  # The primary worktree will switch to $base: that has to be possible before origin changes.
  if printf '%s\n' "$wts" | grep -qxF -- "$main"; then
    printf '%s\n' "$wl" | awk -v m="$main" -v r="branch refs/heads/$base" '/^worktree /{w=substr($0,10)} $0==r && w!=m{f=1} END{exit !f}' \
      && { echo "$base is checked out in another worktree, so $main can't leave $b: stop"; return 1; }
    git rev-parse -q --verify "refs/heads/$base" >/dev/null || git rev-parse -q --verify "refs/remotes/origin/$base" >/dev/null \
      || { echo "no $base branch to switch $main to: stop"; return 1; }
  fi
  # Origin first: GitHub's auto-delete may already have removed it. Delete only
  # while it still points at the merged head; a failed ls-remote stops. Its pattern matches the
  # tail of each ref (feat/x also matches other/feat/x), so compare the listed names exactly.
  rl=$(git ls-remote origin "refs/heads/$b") || { echo "ls-remote failed: stop"; return 1; }
  if printf '%s\n' "$rl" | awk -v r="refs/heads/$b" '$2==r{f=1} END{exit !f}'; then rc=0; else rc=2; fi
  case $rc in
    0) git push --force-with-lease="refs/heads/$b:$oid" origin --delete "$b" \
         || { echo "origin refused the delete (moved since the merge?): keeping $b"; return 1; }
       deleted=1 ;;
    2) echo "origin already deleted $b" ;;
  esac
  # Worktrees: re-check, then remove a linked one, detach one with submodules, or switch the
  # primary (git can't remove those two). If any step fails, put origin's branch back at the
  # merged head and detached worktrees back on $b, so a failure never leaves origin deleted
  # while the local branch stays.
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    if [ "$w" = "$main" ]; then
      s=$(git -C "$w" status --porcelain) && [ -z "$s" ] && git -C "$w" switch "$base"
    elif printf '%s\n' "$dets" | grep -qxF -- "$w"; then
      # No commit argument: it stays at its own HEAD, so no file changes. A failing
      # post-checkout hook makes the switch fail after HEAD detached, so record it either way.
      s=$(git -C "$w" status --porcelain) && [ -z "$s" ] && {
        git -C "$w" switch -q --detach; sw=$?
        git -C "$w" symbolic-ref -q HEAD >/dev/null || detached="$detached$w"$'\n'
        [ "$sw" = 0 ]; }
    else
      s=$(git -C "$w" status --porcelain --ignored) && [ -z "$s" ] && git -C "$main" worktree remove "$w" \
        && _cmb_leave_removed "$w" "$main"
    fi || { echo "couldn't clear $w: keeping $b"; _cmb_reattach "$main" "$b" "$detached"
            _cmb_restore_origin "$main" "$deleted" "$b" "$oid"; return 1; }
  done < <(printf '%s\n' "$wts")
  # Local: refuses unless the tip is still the one checked above (branch -D deletes whatever).
  if [ -n "$tip" ] && ! git -C "$main" update-ref -d "refs/heads/$b" "$tip"; then
    echo "local $b moved mid-run: keeping it"; _cmb_reattach "$main" "$b" "$detached"
    _cmb_restore_origin "$main" "$deleted" "$b" "$oid"; return 1
  fi
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    echo "$w is detached at $(git -C "$w" rev-parse --short HEAD), and git can't remove it (submodules)."
    echo "  It may still hold ignored files. Check it, then Force delete it in Orca, or (not Orca's) run: git worktree remove --force $(printf %q "$w")"
  done < <(printf '%s\n' "$detached")
  git -C "$main" fetch --prune
}
# After removing worktree $1: if that took the shell's directory with it, move the shell to the
# main worktree $2. The function is sourced, so the shell would otherwise sit in a deleted
# directory where every command fails. Only then does it change directory; it never fails.
_cmb_leave_removed() {
  [ -d "${PWD:-.}" ] && return 0
  if builtin cd -- "$2" >/dev/null 2>&1; then echo "the shell was in $1, now removed: moved it to $2"
  else echo "the shell was in $1, now removed, and can't cd to $2: cd somewhere that exists"; fi
  return 0
}
# Put each worktree this run detached back on $2, when $2 still points at its HEAD and no other
# worktree has checked it out since. symbolic-ref only moves HEAD, so no file changes either way.
# $1 is the main worktree, where the repo-wide git calls run.
_cmb_reattach() {
  local w h wl
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    h=$(git -C "$w" rev-parse HEAD) && [ "$(git -C "$1" rev-parse -q --verify "refs/heads/$2")" = "$h" ] \
      && wl=$(git -C "$1" worktree list --porcelain) && ! printf '%s\n' "$wl" | grep -qxF "branch refs/heads/$2" \
      && git -C "$w" symbolic-ref HEAD "refs/heads/$2" && { echo "put $w back on $2"; continue; }
    echo "REATTACH FAILED: $w is detached at ${h:-?}, and $2 is elsewhere, gone, or checked out in another worktree"
  done < <(printf '%s\n' "$3")
}
# Put origin's branch back at the merged head after a failure, if this run deleted it.
# Usage: _cmb_restore_origin <main worktree> <deleted: 1 or 0> <branch> <merged head>
_cmb_restore_origin() {
  [ "$2" = 1 ] || return 0
  if git -C "$1" push -q origin "${4}:refs/heads/$3"; then echo "restored origin/$3"
  else printf 'RESTORE FAILED: origin/%s is deleted; run: git -C %q push origin %q\n' "$3" "$1" "${4}:refs/heads/$3"; fi
}
