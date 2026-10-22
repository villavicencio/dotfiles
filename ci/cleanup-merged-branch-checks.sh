#!/usr/bin/env bash
# Scenario checks for cleanup_merged_branch (bin/lib/cleanup-merged-branch.sh) and the
# `wt done` guard in front of it. Run locally after changing either (not wired into CI):
#
#   ci/cleanup-merged-branch-checks.sh            both shells
#   ci/cleanup-merged-branch-checks.sh zsh        one shell
#
# Each scenario builds a scratch origin and clone with a real submodule (an Orca worktree
# always has dotbot initialized), stubs gh, runs the function in the shell under test, then
# checks origin, the local branch and the worktree. Failures are injected with a git wrapper.
# Needs git, bash and zsh; nothing outside a mktemp dir is touched.
# The checks are eval'd strings, so their $vars are meant to stay unexpanded until then.
# shellcheck disable=SC2016,SC2034
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
if [ $# = 0 ]; then "$0" bash; a=$?; "$0" zsh; exit $((a | $?)); fi
SH=$1
SHFLAGS=$( [ "$SH" = zsh ] && echo -f )  # zsh -f: skip ~/.zshenv, which rebuilds PATH ahead of the stubs
LIB="$REPO/bin/lib/cleanup-merged-branch.sh"
REALGIT=$(command -v git)
pass=0 fail=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

ok()   { pass=$((pass+1)); echo "  ok   $*"; }
bad()  { fail=$((fail+1)); echo "  FAIL $*"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Build: $T/origin.git, $T/sub (submodule source), $T/main (clone on master), branch feat/x
# pushed with one commit. Sets OID (the PR's merged head) and TIP (local branch tip).
setup() {
  # pwd -P: git reports worktree paths resolved (macOS TMPDIR is under the /var link).
  T=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cmb.XXXXXX")" && pwd -P); mkdir -p "$T/bin"
  git init -q -b main "$T/sub" && git -C "$T/sub" commit -q --allow-empty -m sub
  git init -q --bare -b master "$T/origin.git"
  git clone -q "$T/origin.git" "$T/main" 2>/dev/null
  cd "$T/main" || exit 1
  printf 'ignored.txt\n' > .gitignore; echo base > f; git add . && git commit -q -m base
  git -c protocol.file.allow=always submodule -q add "$T/sub" sub && git commit -q -m sub
  git push -q origin master
  git switch -q -c feat/x && echo change >> f && git commit -q -am change && git push -q origin feat/x
  git switch -q master
  OID=$(git rev-parse feat/x) TIP=$OID
  cat > "$T/bin/gh" <<EOF
#!/bin/sh
# gh pr view <N> --json ... -q ...: the merged PR's head
[ "\$1 \$2" = "pr view" ] && { echo "feat/x \$(cat "$T/oid") false"; exit 0; }
[ "\$1 \$2" = "pr list" ] && { echo "7 \$(cat "$T/oid")"; exit 0; }
exit 1
EOF
  chmod +x "$T/bin/gh"; echo "$OID" > "$T/oid"
}
# A linked worktree on feat/x with the submodule initialized, like an Orca worktree.
orca_wt() {
  git worktree add -q "$T/wt" feat/x
  git -C "$T/wt" -c protocol.file.allow=always submodule -q update --init
  [ -e "$(git -C "$T/wt" rev-parse --absolute-git-dir)/modules" ] || echo "setup: no modules dir"
}
run() {  # run [dir]: run the function from dir (default $T/main) under $SH; output in $T/out
  (cd "${1:-$T/main}" && PATH="$T/bin:$PATH" "$SH" ${SHFLAGS:+"$SHFLAGS"} -c ". '$LIB'; cleanup_merged_branch 7 master" >"$T/out" 2>&1)
  RC=$?
}
origin_has() { [ -n "$(git -C "$T/main" ls-remote origin refs/heads/feat/x)" ]; }
origin_at()  { [ "$(git -C "$T/main" ls-remote origin refs/heads/feat/x | cut -f1)" = "$1" ]; }
local_has()  { git -C "$T/main" rev-parse -q --verify refs/heads/feat/x >/dev/null; }
wt_branch()  { git -C "$T/wt" symbolic-ref -q --short HEAD; }
wt_head()    { git -C "$T/wt" rev-parse HEAD; }
done_() { [ "$fail" = "$f0" ] || { echo "  --- output:"; sed 's/^/  | /' "$T/out"; }; cd /; rm -rf "$T"; }

echo "== $SH"

echo "1. Orca-like worktree, clean, run from the main checkout"
f0=$fail; setup; orca_wt; run
check "returns 0" '[ $RC = 0 ]'
check "origin deleted" '! origin_has'
check "local deleted" '! local_has'
check "worktree still there" '[ -d "$T/wt" ]'
check "worktree detached at the tip" '[ -z "$(wt_branch)" ] && [ "$(wt_head)" = "$TIP" ]'
check "says how to remove it" 'grep -q "is detached at" "$T/out" && grep -q "Force delete it in Orca, or" "$T/out"'
done_

echo "2. Same, run from inside the worktree"
f0=$fail; setup; orca_wt; run "$T/wt"
check "returns 0" '[ $RC = 0 ]'
check "origin deleted" '! origin_has'
check "local deleted" '! local_has'
check "worktree detached at the tip" '[ -z "$(wt_branch)" ] && [ "$(wt_head)" = "$TIP" ]'
done_

echo "3. Stale local copy (PR rebased on GitHub), Orca-like worktree"
f0=$fail; setup
git switch -q master && echo other > g && git add g && git commit -q -m other && git push -q origin master
git switch -q --detach master && git cherry-pick feat/x >/dev/null && NEW=$(git rev-parse HEAD)
git push -q -f origin "$NEW:refs/heads/feat/x" && git switch -q master
echo "$NEW" > "$T/oid"; OID=$NEW
orca_wt; before=$(cat "$T/wt/f"); run
check "returns 0" '[ $RC = 0 ]'
check "origin deleted" '! origin_has'
check "local deleted" '! local_has'
check "detached at the stale tip, not the merged head" '[ "$(wt_head)" = "$TIP" ] && [ -z "$(wt_branch)" ]'
check "files unchanged" '[ "$(cat "$T/wt/f")" = "$before" ] && [ ! -e "$T/wt/g" ]'
done_

echo "4. Orca-like worktree with a tracked change"
f0=$fail; setup; orca_wt; echo dirty >> "$T/wt/f"; run
check "returns 1" '[ $RC = 1 ]'
check "origin kept at the merged head" 'origin_at "$OID"'
check "local kept" 'local_has'
check "worktree still on feat/x" '[ "$(wt_branch)" = feat/x ]'
done_

echo "5. Orca-like worktree with only an ignored file"
f0=$fail; setup; orca_wt; echo keep > "$T/wt/ignored.txt"; run
check "returns 0" '[ $RC = 0 ]'
check "origin and local deleted" '! origin_has && ! local_has'
check "detached, ignored file kept" '[ -z "$(wt_branch)" ] && [ "$(cat "$T/wt/ignored.txt")" = keep ]'
done_

echo "6a. Local delete fails after the detach, branch unmoved"
f0=$fail; setup; orca_wt
printf '#!/bin/sh\ncase "$*" in *"update-ref -d refs/heads/feat/x"*) exit 1;; esac\nexec %s "$@"\n' "$REALGIT" > "$T/bin/git"
chmod +x "$T/bin/git"; run; rm "$T/bin/git"
check "returns 1" '[ $RC = 1 ]'
check "origin restored at the merged head" 'origin_at "$OID"'
check "local kept" 'local_has'
check "worktree back on feat/x" '[ "$(wt_branch)" = feat/x ] && [ -z "$(git -C "$T/wt" status --porcelain)" ]'
check "says so" 'grep -q "put $T/wt back on feat/x" "$T/out"'
done_

echo "6b. Local branch moves mid-run, after the detach"
f0=$fail; setup; orca_wt; OTHER=$(git -C "$T/main" rev-parse master)
printf '#!/bin/sh\ncase "$*" in *"update-ref -d refs/heads/feat/x"*) %s update-ref refs/heads/feat/x %s;; esac\nexec %s "$@"\n' \
  "$REALGIT" "$OTHER" "$REALGIT" > "$T/bin/git"
chmod +x "$T/bin/git"; run; rm "$T/bin/git"
check "returns 1" '[ $RC = 1 ]'
check "origin restored at the merged head" 'origin_at "$OID"'
check "local kept (at its new tip)" 'local_has'
check "worktree left detached at its own HEAD" '[ -z "$(wt_branch)" ] && [ "$(wt_head)" = "$TIP" ]'
check "REATTACH FAILED reported" 'grep -q "REATTACH FAILED: $T/wt" "$T/out"'
done_

echo "6c. The detach itself fails"
f0=$fail; setup; orca_wt
printf '#!/bin/sh\ncase "$*" in *"switch -q --detach"*) exit 1;; esac\nexec %s "$@"\n' "$REALGIT" > "$T/bin/git"
chmod +x "$T/bin/git"; run; rm "$T/bin/git"
check "returns 1" '[ $RC = 1 ]'
check "origin restored at the merged head" 'origin_at "$OID"'
check "local kept" 'local_has'
check "worktree still on feat/x" '[ "$(wt_branch)" = feat/x ]'
done_

echo "7. Locked Orca-like worktree"
f0=$fail; setup; orca_wt; git worktree lock "$T/wt"; run
check "returns 1, all kept" '[ $RC = 1 ] && origin_at "$OID" && local_has && [ "$(wt_branch)" = feat/x ]'
done_

echo "8. Linked worktree without submodules is still removed"
f0=$fail; setup; git worktree add -q "$T/wt" feat/x; run
check "returns 0, removed, both deleted" '[ $RC = 0 ] && [ ! -e "$T/wt" ] && ! origin_has && ! local_has'
done_

echo "9. Linked worktree without submodules, ignored file: kept"
f0=$fail; setup; git worktree add -q "$T/wt" feat/x; echo x > "$T/wt/ignored.txt"; run
check "returns 1, all kept" '[ $RC = 1 ] && [ -e "$T/wt/ignored.txt" ] && origin_at "$OID" && local_has'
done_

echo "10. No worktree; origin already deleted; primary on the branch"
f0=$fail; setup; run
check "no worktree: both deleted" '[ $RC = 0 ] && ! origin_has && ! local_has'
done_; f0=$fail; setup; git push -q origin --delete feat/x; run
check "origin gone already: local deleted" '[ $RC = 0 ] && ! local_has && grep -q "origin already deleted" "$T/out"'
done_; f0=$fail; setup; git switch -q feat/x; run
check "primary switched to master, both deleted" '[ $RC = 0 ] && [ "$(git -C "$T/main" branch --show-current)" = master ] && ! origin_has && ! local_has'
done_

echo "11. Local branch has a new commit (Orca-like worktree)"
f0=$fail; setup; orca_wt; echo more >> "$T/wt/f"; git -C "$T/wt" commit -q -am more; run
check "returns 1, all kept, still on branch" '[ $RC = 1 ] && origin_at "$OID" && local_has && [ "$(wt_branch)" = feat/x ]'
done_

echo "12. wt done refuses a worktree with an initialized submodule, before the PR lookup"
# A gh that fails: reaching the PR lookup would stop with gh's error instead of the refusal.
f0=$fail; setup; printf '#!/bin/sh\nexit 1\n' > "$T/bin/gh"; mkdir -p "$T/main/.claude"; echo '{}' > "$T/main/.claude/settings.local.json"
printf '.claude/\n' >> "$T/main/.git/info/exclude"
git worktree add -q "$T/main/.claude/worktrees/x" feat/x
git -C "$T/main/.claude/worktrees/x" -c protocol.file.allow=always submodule -q update --init
mkdir -p "$T/main/.claude/worktrees/x/.claude" && cp "$T/main/.claude/settings.local.json" "$T/main/.claude/worktrees/x/.claude/"
gdx=$(git -C "$T/main/.claude/worktrees/x" rev-parse --absolute-git-dir); echo .claude/settings.local.json > "$gdx/wt-carried"
(cd "$T/main" && PATH="$T/bin:$PATH" "$REPO/bin/wt" "done" x) >"$T/out" 2>&1; RC=$?
check "wt done fails" '[ $RC != 0 ] && grep -q "initialized submodule" "$T/out"'
check "nothing changed" 'origin_at "$OID" && local_has && [ -f "$T/main/.claude/worktrees/x/.claude/settings.local.json" ] && [ ! -d "$gdx/wt-held" ]'
done_

echo "== $SH: $pass passed, $fail failed"
[ "$fail" = 0 ]
