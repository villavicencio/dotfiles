#!/usr/bin/env bash
# Scenario checks for delete_leftover_branch (bin/lib/delete-leftover-branch.sh). Run locally
# after changing it (not wired into CI):
#
#   ci/delete-leftover-branch-checks.sh            both shells
#   ci/delete-leftover-branch-checks.sh zsh        one shell
#
# Each scenario builds a scratch origin and clone, runs the function in the shell under test,
# then checks whether the local branch survived. Failures are injected with a git wrapper.
# Needs git, bash and zsh; nothing outside a mktemp dir is touched.
# The checks are eval'd strings, so their $vars are meant to stay unexpanded until then.
# shellcheck disable=SC2016
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
if [ $# = 0 ]; then "$0" bash; a=$?; "$0" zsh; exit $((a | $?)); fi
SH=$1
SHFLAGS=$( [ "$SH" = zsh ] && echo -f )  # zsh -f: skip ~/.zshenv, which rebuilds PATH ahead of the stubs
LIB="$REPO/bin/lib/delete-leftover-branch.sh"
REALGIT=$(command -v git)
pass=0 fail=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

ok()   { pass=$((pass+1)); echo "  ok   $*"; }
bad()  { fail=$((fail+1)); echo "  FAIL $*"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Build: $T/origin.git (default branch main, two commits), $T/main (clone on main), and a local
# branch `left` at main's first commit, made the way Orca makes one (a worktree on it, then
# the worktree removed). Sets OLD (left's tip) and HEAD_OID (origin's main).
setup() {
  T=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dlb.XXXXXX")" && pwd -P); mkdir -p "$T/bin"
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/main" 2>/dev/null
  cd "$T/main" || exit 1
  echo a > f; git add f && git commit -q -m a; OLD=$(git rev-parse HEAD)
  echo b >> f; git commit -q -am b; git push -q origin main; HEAD_OID=$(git rev-parse HEAD)
  git worktree add -q "$T/wt" -b left "$OLD" && git worktree remove "$T/wt"
}
run() {  # run [branch] [dir]: run the function under $SH; output in $T/out, status in RC
  (cd "${2:-$T/main}" && PATH="$T/bin:$PATH" "$SH" ${SHFLAGS:+"$SHFLAGS"} -c ". '$LIB'; delete_leftover_branch '${1-left}'" >"$T/out" 2>&1)
  RC=$?
}
wrap() {  # wrap <case pattern> <action>: a git that runs <action> when its args match, else real git
  printf '#!/bin/sh\ncase "$*" in %s) %s ;; esac\nexec %s "$@"\n' "$1" "$2" "$REALGIT" > "$T/bin/git"
  chmod +x "$T/bin/git"
}
has()  { git -C "$T/main" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
kept() { [ "$RC" = 1 ] && has "${1:-left}" && grep -q "^keeping" "$T/out"; }
done_() { [ "$fail" = "$f0" ] || { echo "  --- output:"; sed 's/^/  | /' "$T/out"; }; cd /; rm -rf "$T"; }

echo "== $SH"

echo "1. Leftover branch at an older commit of origin's main: deleted"
f0=$fail; setup; git config branch.left.remote origin; run
check "returns 0, branch gone" '[ $RC = 0 ] && ! has left'
check "its config section is gone" '! git config --get branch.left.remote'
check "prints the undo" 'grep -q "to undo: git branch left $OLD" "$T/out"'
check "origin untouched" '[ "$(git -C "$T/origin.git" rev-parse main)" = "$HEAD_OID" ]'
done_

echo "2. Run from a checkout whose branch doesn't contain the tip: still deleted (git branch -d would refuse)"
f0=$fail; setup; git switch -q --orphan other && git commit -q --allow-empty -m other; run
check "returns 0, branch gone" '[ $RC = 0 ] && ! has left'
done_

echo "3. Origin's main was force-pushed past a stale origin/main; no origin/HEAD; a narrow fetch refspec"
f0=$fail; setup; git branch gone "$HEAD_OID"; git update-ref -d refs/remotes/origin/HEAD
git config remote.origin.fetch '+refs/heads/nothing:refs/remotes/origin/nothing'
# Another clone rewrites origin's main to OLD plus a new commit; this clone's origin/main stays at HEAD_OID.
(cd "$T" && git clone -q origin.git c2 2>/dev/null && cd c2 && git reset -q --hard "$OLD" && echo c >> f && git commit -q -am c && git push -q -f origin main)
check "setup: stale origin/main still holds gone's tip" 'git merge-base --is-ancestor gone refs/remotes/origin/main'
run gone; check "gone (only on the stale ref) is kept" 'kept gone && grep -q "tip isn.t on origin.s main" "$T/out"'
run; check "left (on origin's live main, fetched by explicit refspec) is deleted" '[ $RC = 0 ] && ! has left'
done_

echo "4. A stale origin/HEAD naming an old default branch is ignored"
f0=$fail; setup
git switch -q -c side "$OLD" && echo s >> f && git commit -q -am s && git push -q origin side:old-default && git switch -q main && git branch -D side >/dev/null
git fetch -q origin; git branch onold origin/old-default
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/old-default
check "setup: onold is on the cached default" 'git merge-base --is-ancestor onold "$(git symbolic-ref refs/remotes/origin/HEAD)"'
run onold; check "onold is kept: origin's real default is main" 'kept onold && grep -q "origin.s main" "$T/out"'
done_

echo "5. Empty branch name, unknown branch, invalid name, the default branch: kept"
f0=$fail; setup
run ""; check "empty name" '[ $RC = 1 ] && grep -q "^keeping: no branch named" "$T/out" && has left'
run nope; check "unknown branch" '[ $RC = 1 ] && grep -q "no such local branch" "$T/out"'
run "a..b"; check "invalid name" '[ $RC = 1 ] && grep -q "not a valid branch name" "$T/out"'
git checkout -q --detach; run main; check "the default branch, even when nothing has it checked out" 'kept main && grep -q "default branch" "$T/out"'
done_

echo "6. Checked out: in the current checkout, and in a linked worktree"
f0=$fail; setup; git switch -q left; run
check "current branch kept" 'kept && grep -q "checked out" "$T/out"'
git switch -q main; git worktree add -q "$T/wt" left; run
check "linked worktree's branch kept" 'kept && grep -q "checked out" "$T/out"'
done_

echo "7. A worktree is rebasing, or bisecting, from the branch (shown as detached): kept"
f0=$fail; setup; git worktree add -q "$T/wt" left
git -C "$T/wt" rebase -q --root -x false >/dev/null 2>&1
check "setup: worktree shows detached" '! git worktree list --porcelain | grep -qx "branch refs/heads/left"'
run; check "kept mid-rebase" 'kept && grep -q "rebase or bisect" "$T/out"'
git -C "$T/wt" rebase --abort; git -C "$T/wt" bisect start >/dev/null
git -C "$T/wt" checkout -q --detach
check "setup: bisect started from left, worktree detached" '[ -f "$(git -C "$T/wt" rev-parse --absolute-git-dir)/BISECT_START" ]'
run; check "kept mid-bisect" 'kept && grep -q "rebase or bisect" "$T/out"'
done_
f0=$fail; setup; git switch -q left; git rebase -q --root -x false >/dev/null 2>&1
check "setup: the main checkout is mid-rebase from left, detached" '[ -z "$(git branch --show-current)" ] && [ -d .git/rebase-merge ]'
run; check "kept when the main checkout is rebasing it" 'kept && grep -q "rebase or bisect" "$T/out"'
git rebase --abort
done_
f0=$fail; setup; git worktree add -q --detach "$T/wt" "$OLD"; gdw=$(git -C "$T/wt" rev-parse --absolute-git-dir)
mkdir "$gdw/rebase-merge" && echo refs/heads/other > "$gdw/rebase-merge/head-name" && chmod 000 "$gdw/rebase-merge/head-name"
run; chmod 644 "$gdw/rebase-merge/head-name"
check "kept when a worktree's rebase state can't be read" 'kept && grep -q "rebase or bisect" "$T/out"'
done_

echo "8. The reflog holds a commit reset off the branch: kept"
f0=$fail; setup; git switch -q left && echo y >> f && git commit -q -am y && git reset -q --hard "$OLD" && git switch -q main; run
check "kept" 'kept && grep -q "reflog holds commits" "$T/out"'
done_

echo "9. No reflog, an unreadable reflog, a reflog naming a missing commit: kept"
f0=$fail; setup; rm .git/logs/refs/heads/left; run
check "no reflog" 'kept && grep -q "no reflog" "$T/out"'
done_
f0=$fail; setup; chmod 000 .git/logs/refs/heads/left; run; chmod 644 .git/logs/refs/heads/left
check "unreadable reflog" 'kept'
done_
f0=$fail; setup; git switch -q left && echo z >> f && git commit -q -am z; Z=$(git rev-parse HEAD); git reset -q --hard "$OLD"; git switch -q main
rm -f ".git/objects/$(printf %s "$Z" | cut -c1-2)/$(printf %s "$Z" | cut -c3-)"; run
check "setup: git log -g skips the missing entry" '! git log -g --format=%H refs/heads/left -- | grep -q "$Z"'
check "reflog naming a missing commit" 'kept && grep -q "couldn.t check its reflog" "$T/out"'
done_

echo "10. Origin can't be asked, names no default branch, or the commit can't be fetched: kept"
f0=$fail; setup; git remote set-url origin "$T/nowhere.git"; run
check "origin unreachable" 'kept && grep -q "couldn.t ask origin" "$T/out"'
done_
f0=$fail; setup; wrap '"ls-remote --symref origin HEAD"' "printf '%s\\tHEAD\\n' $HEAD_OID; exit 0"; run
check "ls-remote gives no symref (empty default name)" 'kept && grep -q "didn.t name a default branch" "$T/out"'
done_
f0=$fail; setup; wrap '"ls-remote --symref origin HEAD"' 'printf "ref: refs/heads/main\tHEAD\n"; exit 0'; run
check "ls-remote gives no commit (empty oid)" 'kept && grep -q "didn.t give its default branch.s commit" "$T/out"'
done_
f0=$fail; setup; wrap '"ls-remote --symref origin HEAD"' 'printf "ref: refs/heads/main\tHEAD\n%s\tHEAD\n" 1111111111111111111111111111111111111111; exit 0'; run
check "origin's commit isn't here and the fetch can't get it" 'kept && grep -q "couldn.t fetch" "$T/out"'
done_
f0=$fail; setup; (cd "$T" && git clone -q origin.git c2 2>/dev/null && cd c2 && echo c >> f && git commit -q -am c && git push -q origin main)
wrap '"fetch"*' 'exit 1'; run
check "origin moved on and the fetch fails" 'kept && grep -q "couldn.t fetch" "$T/out"'
done_

echo "11. Each later git command fails: kept"
for pat in '"check-ref-format"*' '"rev-parse -q --verify refs/heads/left^{commit}"' '"merge-base --is-ancestor"*' '"log -g"*' '"rev-list --stdin"*' '"worktree list"*' '"rev-parse --path-format=absolute --git-common-dir"' '"update-ref -d"*'; do
  f0=$fail; setup; wrap "$pat" 'exit 1'; run; rm "$T/bin/git"
  check "$pat fails" 'kept'
  done_
done

f0=$fail; setup; git branch -f left "$HEAD_OID"; git branch -f left "$OLD"
check "setup: a 3-entry reflog, all on main" '[ "$(git log -g --format=%H refs/heads/left -- | wc -l)" -eq 3 ]'
wrap '"rev-parse -q --verify refs/heads/left@{1}"' 'exit 128'; run
check "reading the reflog by number stops early" 'kept && grep -q "couldn.t read its reflog" "$T/out"'
done_
f0=$fail; setup; printf '#!/bin/sh\nexit 2\n' > "$T/bin/grep"; chmod +x "$T/bin/grep"; run
check "grep on the worktree list fails" 'kept && grep -q "couldn.t read the worktree list" "$T/out"'
done_

echo "12. The branch moves between the checks and the delete: kept at its new tip"
f0=$fail; setup; wrap '"update-ref -d refs/heads/left"*' "$REALGIT update-ref refs/heads/left \$($REALGIT rev-parse main)"; run; rm "$T/bin/git"
check "kept, at main's commit" 'kept && [ "$(git rev-parse left)" = "$HEAD_OID" ]'
done_

echo "== $SH: $pass passed, $fail failed"
[ "$fail" = 0 ]
