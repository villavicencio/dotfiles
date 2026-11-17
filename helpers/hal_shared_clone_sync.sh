#!/usr/bin/env bash
#
# hal_shared_clone_sync.sh — step 1 of "One dotfiles clone on hal" in
# docs/reference/install-and-server.md (VIL-700 part 2): bring `david`'s and `hal`'s dotfiles
# clones on hal to one commit, GitHub's master as this script reads it, and confirm it.
#
# Personal Mac only, run by hand, as David's own account, from the dotfiles checkout:
#
#   bash helpers/hal_shared_clone_sync.sh
#
# It reaches `david` with `ssh hal` and `hal` with `ssh hal-as-hal` (set up by "Reaching hal as
# `hal`"). First it reads master's commit from GitHub and checks both clones without changing
# them: each must be on `master` with no edits to tracked files, and its `origin` must be
# GitHub's URL (with or without .git). Only when both pass does it fast-forward each clone to exactly that commit
# (`git fetch`, then `git merge --ff-only <commit>`), then read both again.
#
# Exit: 0 both clones are on the commit (or DOTFILES_DRY_RUN=1 and both checks passed: the dry
# run reads, prints what it would do, and changes nothing). 1 a check failed or ssh failed
# before anything was changed; nothing changed. 4 a fast-forward failed, or the clones didn't
# end on the commit; the last lines show where each one is. Running it again is safe: it only
# fast-forwards, and a clone already on the commit is left alone.
#
# Overrides, for ci/hal-shared-clone-checks.sh only: HAL_SHARED_SSH (the ssh command) and
# HAL_SHARED_REMOTE (the URL standing in for GitHub's).
set -uo pipefail

SSH="${HAL_SHARED_SSH:-ssh}"
REMOTE="${HAL_SHARED_REMOTE:-https://github.com/villavicencio/dotfiles.git}"
DRY=${DOTFILES_DRY_RUN:-0}

# Runs on hal, sent over ssh as a function. Args: check|ff, the commit, the expected origin URL.
# shellcheck disable=SC2329
_clone_side() {
  local act=$1 want=$2 url=$3 c=$HOME/Projects/Personal/dotfiles b h dirty o
  local who
  who=$(id -un)
  [ -d "$c/.git" ] || { echo "$who: no clone at $c"; return 1; }
  cd "$c" || return 1
  # With or without the trailing .git: hal's own clone was made without it.
  o=$(git remote get-url origin 2>/dev/null)
  [ "${o%.git}" = "${url%.git}" ] || { echo "$who: origin of $c is ${o:-unset}, not $url"; return 1; }
  b=$(git symbolic-ref -q --short HEAD) || b=detached
  h=$(git rev-parse -q --verify HEAD) || { echo "$who: can't read HEAD in $c"; return 1; }
  echo "$who: $c on $b at ${h:0:7}"
  # A failed status is "can't tell", never "clean".
  dirty=$(git --no-optional-locks status --porcelain --untracked-files=no) ||
    { echo "$who: git status failed in $c, so it can't tell whether tracked files have edits"; return 1; }
  dirty=$(printf '%s\n' "$dirty" | awk 'NF && NR <= 5')
  [ "$b" = master ] || { echo "$who: not on master"; return 1; }
  [ -z "$dirty" ] || { echo "$who: edits to tracked files:"; printf '    %s\n' "$dirty"; return 1; }
  if [ "$h" = "$want" ]; then echo "$who: already on ${want:0:7}"; return 0; fi
  if [ "$act" = check ]; then echo "$who: not on ${want:0:7}"; return 0; fi
  git fetch -q origin master || { echo "$who: fetch failed; the clone is unchanged"; return 4; }
  git merge -q --ff-only "$want" || { echo "$who: fast-forward to ${want:0:7} failed"; return 4; }
  h=$(git rev-parse HEAD) || h=unknown
  [ "$h" = "$want" ] || { echo "$who: ended on ${h:0:7}, not ${want:0:7} (local commits?)"; return 4; }
  echo "$who: now on ${want:0:7}"
}

# remote <alias> <act>: run _clone_side on hal under that alias.
remote() {
  "$SSH" -o BatchMode=yes "$1" bash -s -- "$2" "$want" "$REMOTE" < <(declare -f _clone_side; echo '_clone_side "$@"')
}

[[ $REMOTE =~ ^[A-Za-z0-9:/._-]+$ ]] || { echo "unexpected remote URL; nothing sent" >&2; exit 1; }
want=$(git ls-remote "$REMOTE" refs/heads/master 2>/dev/null | cut -f1)
[[ $want =~ ^[0-9a-f]{40}$ ]] || { echo "couldn't read master from $REMOTE; nothing changed" >&2; exit 1; }
echo "GitHub's master: $want"

rc=0
for a in hal hal-as-hal; do
  remote "$a" check; r=$?
  [ "$r" = 0 ] || { echo "check over ssh $a failed (exit $r)" >&2; rc=1; }
done
[ "$rc" = 0 ] || { echo "Stopped before changing anything." >&2; exit 1; }
if [ "$DRY" = 1 ]; then echo "[dry-run] a real run fast-forwards each clone that isn't on ${want:0:7}. Nothing changed."; exit 0; fi

for a in hal hal-as-hal; do
  remote "$a" ff || echo "fast-forward over ssh $a failed; see above" >&2
done
echo "now:"
rc=0
for a in hal hal-as-hal; do
  out=$(remote "$a" check 2>&1) || rc=4
  printf '%s\n' "$out"
  case $out in *"already on ${want:0:7}"*) ;; *) rc=4 ;; esac
done
if [ "$rc" = 0 ]; then echo "both clones are on ${want:0:7}"; else echo "the clones aren't both on ${want:0:7}; see above" >&2; fi
exit "$rc"
