# shellcheck shell=bash
# cleanup_merged_branch: delete a merged PR's branch locally and on origin.
# Source this file (bash or zsh), then run it from any worktree of the repo:
#   source <dotfiles clone>/bin/lib/cleanup-merged-branch.sh   (~/Projects/Personal/dotfiles on the desk Macs)
#   cleanup_merged_branch <pr> <default branch>
# Why each check exists: docs/agents/code-review.md, "After the merge". bin/wt's
# `wt done` calls it too. This file is the only copy; edit it here.

# Delete a merged PR's branch locally and on origin. Usage: cleanup_merged_branch <pr> <base>
# Fails closed: every check runs before anything changes (including that each worktree step
# can succeed), every failure returns 1, and the step that can delete files (removing a
# worktree) runs only after origin accepted the delete.
cleanup_merged_branch() {
  local N=$1 base=$2 b oid cross tip cherry merges wl main wts w s rc gd deleted=0
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
  wts=$(printf '%s\n' "$wl" | awk -v r="branch refs/heads/$b" '/^worktree /{w=substr($0,10)} $0==r{print w}')
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    if [ "$w" = "$main" ]; then s=$(git -C "$w" status --porcelain) || return 1
    else
      s=$(git -C "$w" status --porcelain --ignored) || return 1
      # `git worktree remove` refuses a locked worktree and one with submodules.
      printf '%s\n' "$wl" | awk -v t="$w" '/^worktree /{c=(substr($0,10)==t)} c && /^locked/{f=1} END{exit !f}' \
        && { echo "$w is locked: keeping $b"; return 1; }
      gd=$(git -C "$w" rev-parse --absolute-git-dir) || return 1
      [ ! -e "$gd/modules" ] || { echo "$w has initialized submodules: keeping $b"; return 1; }
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
  # Origin first: GitHub's auto-delete may already have removed it (exit 2). Delete only
  # while it still points at the merged head; any other ls-remote exit is a failed lookup.
  git ls-remote --exit-code origin "refs/heads/$b" >/dev/null; rc=$?
  case $rc in
    0) git push --force-with-lease="refs/heads/$b:$oid" origin --delete "$b" \
         || { echo "origin refused the delete (moved since the merge?): keeping $b"; return 1; }
       deleted=1 ;;
    2) echo "origin already deleted $b" ;;
    *) echo "ls-remote failed ($rc): stop"; return 1 ;;
  esac
  # Worktrees: re-check, then remove a linked one, or switch the primary (git can't remove it).
  # If any step fails, put origin's branch back at the merged head, so a failure never leaves
  # origin deleted while the local branch stays.
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    if [ "$w" = "$main" ]; then
      s=$(git -C "$w" status --porcelain) && [ -z "$s" ] && git -C "$w" switch "$base"
    else
      s=$(git -C "$w" status --porcelain --ignored) && [ -z "$s" ] && git worktree remove "$w"
    fi || { echo "couldn't clear $w: keeping $b"; _cmb_restore_origin "$deleted" "$b" "$oid"; return 1; }
  done < <(printf '%s\n' "$wts")
  # Local: refuses unless the tip is still the one checked above (branch -D deletes whatever).
  if [ -n "$tip" ] && ! git update-ref -d "refs/heads/$b" "$tip"; then
    echo "local $b moved mid-run: keeping it"; _cmb_restore_origin "$deleted" "$b" "$oid"; return 1
  fi
  git fetch --prune
}
# Put origin's branch back at the merged head after a failure, if this run deleted it.
_cmb_restore_origin() {
  [ "$1" = 1 ] || return 0
  if git push -q origin "${3}:refs/heads/$2"; then echo "restored origin/$2"
  else printf 'RESTORE FAILED: origin/%s is deleted; run: git push origin %q\n' "$2" "${3}:refs/heads/$2"; fi
}
