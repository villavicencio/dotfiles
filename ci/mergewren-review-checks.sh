#!/usr/bin/env bash
# Scenario checks for mergewren_review (bin/lib/mergewren-review.sh) against a stub gh. Run
# locally after changing the function (not wired into CI):
#
#   ci/mergewren-review-checks.sh            both shells
#   ci/mergewren-review-checks.sh zsh        one shell
#
# The stub answers `gh pr view` from $T/head and $T/draft, and `gh api` by running the
# function's own --jq filter over $T/comments.json, so the author and marker filter is real.
# A scenario changes that state between calls by leaving a directory $T/poll.<n> (copied into $T
# at the nth `gh pr view --json headRefOid,isDraft`, one per poll) or $T/recheck.<n> (at the nth
# head re-check after a comment was read). Needs bash, zsh and jq; nothing outside a mktemp dir
# is touched. It doesn't exercise --paginate: the stub returns every comment in one page.
# The checks are eval'd strings, so their $vars are meant to stay unexpanded until then.
# shellcheck disable=SC2016,SC2034
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
if [ $# = 0 ]; then "$0" bash; a=$?; "$0" zsh; exit $((a | $?)); fi
SH=$1
SHFLAGS=$( [ "$SH" = zsh ] && echo -f )  # zsh -f: skip ~/.zshenv, which rebuilds PATH ahead of the stub
LIB="$REPO/bin/lib/mergewren-review.sh"
A=aaaaaaa1111111111111111111111111111111111 B=bbbbbbb2222222222222222222222222222222222
pass=0 fail=0

ok()  { pass=$((pass+1)); echo "  ok   $*"; }
bad() { fail=$((fail+1)); echo "  FAIL $*"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/mwr.XXXXXX"); mkdir -p "$T/bin"
  echo "$A" > "$T/head"; echo false > "$T/draft"; echo '[]' > "$T/comments.json"
  cat > "$T/bin/gh" <<'EOF'
#!/bin/sh
# Every call is logged; a missing state file or an unknown call fails like gh would.
T=$MWR_T; echo "$*" >> "$T/calls"
event() {  # event <name>: count it, then apply $T/<name>.<n> if the scenario left one
  n=$(( $(cat "$T/$1.count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$T/$1.count"
  [ ! -d "$T/$1.$n" ] || cp "$T/$1.$n"/* "$T/"
}
json='' jqf='' path=''
prev=''
for a in "$@"; do
  case $prev in --json) json=$a ;; --jq|-q) jqf=$a ;; esac
  case $a in repos/*) path=$a ;; esac
  prev=$a
done
case "$1 $2" in
  "pr view")
    case $json in
      headRefOid,isDraft) event poll; echo "$(cat "$T/head") $(cat "$T/draft")"; exit 0 ;;
      headRefOid) event recheck; cat "$T/head"; exit 0 ;;
    esac ;;
  "api --paginate")
    [ ! -e "$T/fail-list" ] || { echo "HTTP 502" >&2; exit 1; }
    case $path in */comments\?per_page=100) jq -r "$jqf" "$T/comments.json"; exit ;; esac ;;
  api\ repos/*)
    id=${path##*/}
    jq --argjson id "$id" -e '.[] | select(.id == $id)' "$T/comments.json" | jq -r "$jqf"; exit ;;
esac
echo "gh stub: unexpected call: $*" >&2; exit 1
EOF
  chmod +x "$T/bin/gh"
}
# comment <id> <user> <head> <text>: one review-comment object, marker first like MergeWren's
comment() {
  jq -n --argjson id "$1" --arg u "$2" --arg h "$3" --arg t "$4" '{id: $id, user: {login: $u},
    body: ("<!-- review-stack:head=\($h) run=r\($id) -->\n## Review\n\n<!-- mergewren:verdict_start -->\n" + $t + "\n<!-- mergewren:verdict_end -->\n\nfindings")}'
}
# state <dir> <head> <comment objects...>: write a head and comment list into dir
state() {
  local d=$1 h=$2; shift 2; mkdir -p "$d"; echo "$h" > "$d/head"
  if [ $# -gt 0 ]; then printf '%s\n' "$@" | jq -s . > "$d/comments.json"; else echo '[]' > "$d/comments.json"; fi
}
run() {  # run [wait_s]: call the function for PR 7 under $SH; stdout in $T/out, stderr in $T/err
  PATH="$T/bin:$PATH" MWR_T="$T" MERGEWREN_POLL_S=0 MERGEWREN_WAIT_S="${1:-5}" \
    "$SH" ${SHFLAGS:+"$SHFLAGS"} -c ". '$LIB'; mergewren_review 7 o/r" >"$T/out" 2>"$T/err"
  RC=$?
}
polls() { cat "$T/poll.count" 2>/dev/null || echo 0; }
done_() {
  [ "$fail" = "$f0" ] || { echo "  --- stdout:"; sed 's/^/  | /' "$T/out"; echo "  --- stderr:"; sed 's/^/  | /' "$T/err"; }
  rm -rf "$T"
}

MERGEABLE='MergeWren: mergeable — 0 open at medium+'
PLACEHOLDER='MergeWren: no verdict — incremental round; full confirmation of `aaaaaaa` queued'
INCOMPLETE='MergeWren: no verdict — review incomplete'

echo "== $SH"

echo "1. A verdict on the current head"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$MERGEABLE")"; run
check "returns 0" '[ $RC = 0 ]'
check "prints the comment" 'grep -qF "$MERGEABLE" "$T/out"'
done_

echo "2. Placeholder, then the full review of the same head"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$PLACEHOLDER")"
state "$T/poll.3" "$A" "$(comment 1 villavicencio "$A" "$PLACEHOLDER")" "$(comment 2 villavicencio "$A" "$MERGEABLE")"
run
check "returns 0" '[ $RC = 0 ]'
check "waited past the placeholder" '[ "$(polls)" = 3 ]'
check "prints the full review" 'grep -qF "$MERGEABLE" "$T/out" && ! grep -q "full confirmation" "$T/out"'
done_

echo "3. Placeholder with a declined count, then the full review"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$PLACEHOLDER · 1 declined")"
state "$T/poll.2" "$A" "$(comment 1 villavicencio "$A" "$PLACEHOLDER · 1 declined")" "$(comment 2 villavicencio "$A" "$MERGEABLE")"
run
check "returns 0" '[ $RC = 0 ]'
check "waited past the placeholder" '[ "$(polls)" = 2 ]'
done_

echo "4. Placeholder and nothing after it"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$PLACEHOLDER")"; run 0
check "returns 2 (PENDING)" '[ $RC = 2 ] && grep -q "^PENDING" "$T/err"'
done_

echo "5. A final no verdict: review incomplete"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$INCOMPLETE")"; run
check "returns 5 at once" '[ $RC = 5 ] && [ "$(polls)" = 1 ]'
check "prints the comment" 'grep -qF "$INCOMPLETE" "$T/out"'
check "says it isn't a pass" 'grep -q "^NO VERDICT: .*isn.t a pass" "$T/err"'
done_

echo "6. Other final no-verdict lines"
for line in 'MergeWren: no verdict — incremental round, not a full review' \
            'MergeWren: no verdict — the secret scan did not finish' \
            'MergeWren: no verdict — the secret-scan record could not be verified'; do
  f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$line")"; run
  check "returns 5: ${line#MergeWren: no verdict — }" '[ $RC = 5 ] && [ "$(polls)" = 1 ]'
  done_
done

echo "7. A final no verdict, then a push during the lookup"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$INCOMPLETE")"
state "$T/recheck.1" "$B" "$(comment 1 villavicencio "$A" "$INCOMPLETE")"
state "$T/poll.3" "$B" "$(comment 1 villavicencio "$A" "$INCOMPLETE")" "$(comment 2 villavicencio "$B" "$MERGEABLE")"
run
check "returns 0 for the new head" '[ $RC = 0 ] && [ "$(polls)" = 3 ]'
check "prints only the new head's review" 'grep -q "head=$B" "$T/out" && ! grep -qF "$INCOMPLETE" "$T/out"'
done_

echo "8. A finding that quotes a no-verdict line under a real verdict"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "$MERGEABLE
$INCOMPLETE")"; run
check "returns 0" '[ $RC = 0 ]'
done_

echo "9. Only David's comment starting with the marker counts"
f0=$fail; setup; state "$T" "$A" "$(comment 1 someone-else "$A" "$MERGEABLE")"; run 0
check "another author's copy is ignored (PENDING)" '[ $RC = 2 ]'
done_

echo "10. The other exits are unchanged"
f0=$fail; setup; state "$T" "$A" "$(comment 1 villavicencio "$A" "no verdict line here")"; run
check "no verdict line returns 4 with the comment" '[ $RC = 4 ] && grep -q "no verdict line here" "$T/out"'
done_
f0=$fail; setup; echo true > "$T/draft"; run
check "a draft returns 3" '[ $RC = 3 ]'
done_
f0=$fail; setup; touch "$T/fail-list"; run
check "a failed comment listing returns 1" '[ $RC = 1 ] && grep -q "^ERROR" "$T/err"'
done_

echo "$SH: $pass passed, $fail failed"
[ "$fail" = 0 ]
