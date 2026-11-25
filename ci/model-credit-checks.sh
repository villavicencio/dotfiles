#!/usr/bin/env bash
#
# model-credit-checks.sh — run bin/model-credit against fixtures: local git repos behind a fake
# `gh` (ci/model-credit-fake-gh.py) and a file standing in for Linear's answer. No network, no
# 1Password, nothing outside a mktemp dir. Run by hand after changing bin/model-credit or
# bin/lib/model-credit.py; not in CI.
#
#   ci/model-credit-checks.sh        exit 0 when every case behaves
#
# GitHub's page size is set to 2, so every list the command reads spans several pages.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
ln -s "$REPO/ci/model-credit-fake-gh.py" "$T/bin/gh"
# The fixture commits must not pick up the caller's git config (signing, hooks, templates).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=fixture \
  GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=fixture \
  GIT_COMMITTER_EMAIL=fixture@example.invalid
fail=0 tick=0
A='Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'   # label claude-opus-5-5
B='Worker-Model: qwen3.8-27b'                                  # label qwen3-8-27b

# case_ <name> <ticket> <linear createdAt> [attached PR url...]: start a case.
case_() {
  CASE="$T/$1" TICKET=$2; mkdir -p "$CASE/gh"; echo "== $1"
  python3 -c 'import json, sys
print(json.dumps({"data": {"issue": {"identifier": sys.argv[1], "createdAt": sys.argv[2],
  "attachments": {"pageInfo": {"hasNextPage": False}, "nodes": [{"url": u} for u in sys.argv[3:]]}}}}))' \
    "$2" "$3" "${@:4}" > "$CASE/linear.json"
}
# repo <owner/name>: a fake GitHub repo with an empty first commit on main; later calls work in it.
repo() {
  R="$CASE/gh/$1"; SLUG=$1
  git init -q -b main "$R" && git -C "$R" remote add origin "https://github.com/$1.git"
  echo main > "$CASE/gh/$1.default"
  c - 0 "initial"
}
# c <file|-> <n> <paragraph>...: commit adding n lines to file (- for none), one -m per paragraph.
c() {
  local f=$1 n=$2 i args=(); shift 2
  tick=$((tick + 1))
  [ "$f" = - ] || for ((i = 1; i <= n; i++)); do echo "$tick.$i" >> "$R/$f"; done
  for i in "$@"; do args+=(-m "$i"); done
  git -C "$R" add -A
  stamp git -C "$R" commit -q --allow-empty "${args[@]}"
}
# stamp <cmd...>: run a git command with the next fixture date as author and committer date.
stamp() {
  local d; d=$(printf '2026-03-01T%02d:%02d:00Z' $((tick / 60)) $((tick % 60)))
  GIT_AUTHOR_DATE=$d GIT_COMMITTER_DATE=$d "$@"
}
br() { git -C "$R" checkout -q "$@"; }
sha() { git -C "$R" rev-parse "$1"; }
# squash <branch> <subject>: squash-merge branch into main, as GitHub's squash merge does.
squash() {
  br main && git -C "$R" merge -q --squash "$1" >/dev/null && tick=$((tick + 1)) &&
    stamp git -C "$R" commit -q -m "$2"
}
# pr <number> <head_ref> <head sha> <merge sha> <title> [body]: record a merged PR.
pr() {
  python3 -c 'import json, os, sys
f = sys.argv[1]; d = json.load(open(f)) if os.path.exists(f) else []
d.append({"number": int(sys.argv[2]), "head_ref": sys.argv[3], "head": sys.argv[4],
          "merge": sys.argv[5], "title": sys.argv[6], "body": sys.argv[7] if len(sys.argv) > 7 else None})
json.dump(d, open(f, "w"))' "$CASE/gh/$SLUG.prs.json" "$@"
}
# run [args]: run model-credit from the case's first repo (its "current clone").
run() {
  OUT=$(cd "$R" && PATH="$T/bin:$PATH" FAKE_GH_ROOT="$CASE/gh" \
    MODEL_CREDIT_LINEAR_FIXTURE="$CASE/linear.json" MODEL_CREDIT_PER_PAGE=2 \
    "$REPO/bin/model-credit" "$TICKET" "$@" 2>&1); RC=$?
  SHOWN=0
}
show() { [ "$SHOWN" = 1 ] || { printf '%s\n' "$OUT" | sed 's/^/        | /'; SHOWN=1; }; }
has() {   # has <what> <ERE>: the output has a line matching
  if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -Eq -- "$2"; then echo "ok      $1"
  else echo "FAIL    $1 (rc=$RC, no line matching: $2)"; show; fail=1; fi
}
lacks() { # lacks <what> <ERE>: no output line matches
  if [ "$RC" = 0 ] && ! printf '%s\n' "$OUT" | grep -Eq -- "$2"; then echo "ok      $1"
  else echo "FAIL    $1 (rc=$RC, a line matches: $2)"; show; fail=1; fi
}
model() { has "$1: $2 lines" "^  $1 +$2 lines"; }
nobody() { has "nobody ($1): $2 lines" "^  \(nobody: $1\) +$2 lines"; }
label() { has "label $1" "^Label: $1\$"; }

# --- a PR linked only by its branch name ------------------------------------------------
case_ branch-linked VIL-11 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-11-thing; c a 10 "add a thing" "$A"; h=$(sha HEAD)
squash feat/vil-11-thing "add a thing (#1)"; pr 1 feat/vil-11-thing "$h" "$(sha HEAD)" "add a thing"
run
has "the PR is found by its branch" "acme/app#1  merged  found by: branch "
model claude-opus-5-5 10
label claude-opus-5-5

# --- two PRs, one found through the title and one through the body ------------------------
case_ two-prs VIL-12 2026-02-01T00:00:00Z
repo acme/app
br -b one; c a 10 "first part" "$A"; h=$(sha HEAD); squash one "first part (VIL-12) (#1)"
pr 1 one "$h" "$(sha HEAD)" "first part (VIL-12)"
br -b two; c b 30 "second part" "$B"; h=$(sha HEAD); squash two "second part (#2)"
pr 2 two "$h" "$(sha HEAD)" "second part" "Fixes VIL-12"
run
has "PR #1 counted (title)" "acme/app#1  merged  found by: title "
has "PR #2 counted (body)" "acme/app#2  merged  found by: body "
model claude-opus-5-5 10
model qwen3-8-27b 30
has "the squash commit of PR #1 is not counted again" "lands PR #1; counted above"
label qwen3-8-27b

# --- a PR in a second repo, linked only by a Linear attachment ----------------------------
case_ linear-attachment VIL-13 2026-02-01T00:00:00Z https://github.com/acme/other/pull/7
repo acme/other
br -b x; c a 4 "unrelated title" "$A"; h=$(sha HEAD); squash x "unrelated title (#7)"
pr 7 x "$h" "$(sha HEAD)" "unrelated title"
repo acme/app
c a 3 "a direct fix" "$B"
run
has "the other repo is searched, from the attachment" "^  acme/other  \(Linear attachment\)"
has "the current clone is searched" "^  acme/app  \(current clone\)"
has "the attached PR is counted" "acme/other#7  merged  found by: Linear attachment "
model claude-opus-5-5 4
label claude-opus-5-5

# --- a no-PR commit on the default branch, read from GitHub, not the checkout -------------
case_ no-pr VIL-14 2026-02-01T00:00:00Z
repo acme/app
c a 7 "fix the thing (VIL-14)" "$A"
br -b side; c c 5 "an unrelated PR names VIL-14 in its squash" "$B"; h=$(sha HEAD)
squash side "unrelated, mentions VIL-14 (#3)"; pr 3 side "$h" "$(sha HEAD)" "unrelated"
br -b elsewhere; c z 99 "checked out, not on main (VIL-14)" "$B"
run
has "the direct commit is counted" "^      from acme/app no-PR commit on main: fix the thing \(VIL-14\)"
has "a squash of an unlinked PR is skipped" "lands PR #3; that PR isn't linked to the ticket"
lacks "the checked-out branch is not read" "checked out, not on main"
model claude-opus-5-5 7
label claude-opus-5-5

# --- VIL-85 does not match VIL-852 -------------------------------------------------------
case_ exact-id VIL-85 2026-02-01T00:00:00Z
repo acme/app
br -b pilot/vil-852-20261119; c a 50 "other ticket (VIL-852)" "$B"; h=$(sha HEAD)
squash pilot/vil-852-20261119 "other ticket (VIL-852) (#1)"
pr 1 pilot/vil-852-20261119 "$h" "$(sha HEAD)" "other ticket (VIL-852)" "Refs VIL-852"
c a 40 "direct, other ticket VIL-852" "$B"
br -b feat/vil-85-x; c b 5 "this ticket" "$A"; h=$(sha HEAD)
squash feat/vil-85-x "this ticket (#2)"; pr 2 feat/vil-85-x "$h" "$(sha HEAD)" "this ticket"
br -b feat/vil-85feature; c d 30 "a letter right after the number" "$B"; h=$(sha HEAD)
squash feat/vil-85feature "letter (#3)"; pr 3 feat/vil-85feature "$h" "$(sha HEAD)" "letter" "see VIL-85a"
c e 20 "an underscore right after the number, VIL-85_extra" "$B"
run
has "PR #2 is found by its branch, feat/vil-85-x" "acme/app#2  merged  found by: branch "
lacks "PR #3 (feat/vil-85feature, VIL-85a) is not counted" "acme/app#3 "
lacks "the VIL-85_extra direct commit is not counted" "underscore right after"
lacks "PR #1 (VIL-852) is not counted" "acme/app#1 "
lacks "the VIL-852 direct commit is not counted" "direct, other ticket"
lacks "qwen3-8-27b gets no lines" "qwen3-8-27b"
model claude-opus-5-5 5
label claude-opus-5-5

# --- an untrailered commit, and a lower-case trailer as GitHub writes it -----------------
case_ untrailered VIL-15 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-15; c a 10 "with a trailer" "co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>"
c b 4 "no trailer at all"; c b 2 "a trailer outside the last paragraph" "$A" "Signed-off-by: x"
h=$(sha HEAD); squash feat/vil-15 "work (#1)"; pr 1 feat/vil-15 "$h" "$(sha HEAD)" "work"
run
model claude-opus-5-5 10
nobody "no model trailer" 6
label claude-opus-5-5

# --- untrailered lines outnumber the top model: no label --------------------------------
case_ untrailered-wins VIL-16 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-16; c a 5 "with a trailer" "$A"; c b 8 "no trailer"
h=$(sha HEAD); squash feat/vil-16 "work (#1)"; pr 1 feat/vil-16 "$h" "$(sha HEAD)" "work"
run
model claude-opus-5-5 5
nobody "no model trailer" 8
label "no label: lines in commits that name no model \(8\) are more than claude-opus-5-5's \(5\)"

# --- a merge of the base branch into the PR is skipped ----------------------------------
case_ base-merge VIL-17 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-17; c a 6 "the work" "$A"
br main; c m 100 "meanwhile on main" "$B"
br feat/vil-17; tick=$((tick + 1)); stamp git -C "$R" merge -q --no-edit -m "Merge main into feat/vil-17" -m "$B" main
h=$(sha HEAD); squash feat/vil-17 "the work (#1)"; pr 1 feat/vil-17 "$h" "$(sha HEAD)" "the work"
run
has "the merge of main is skipped" "acme/app#1: merge of the base branch into the PR"
model claude-opus-5-5 6
lacks "main's own commit is not counted" "meanwhile on main"
label claude-opus-5-5

# --- a merge inside a PR: the commits it merged count, and so does its conflict fix ------
case_ inner-merge VIL-23 2026-02-01T00:00:00Z
repo acme/app
c g 1 "base for the conflict"
br -b feat/vil-23; c a 3 "pr work" "$A"; printf 'pr side\n' > "$R/g"; c - 0 "pr edits g" "$A"
br -b sub HEAD~1; c b 10 "sub-branch work" "$B"; printf 'sub side\n' > "$R/g"; c - 0 "sub edits g" "$B"
br feat/vil-23; tick=$((tick + 1)); stamp git -C "$R" merge -q --no-ff -m x sub >/dev/null 2>&1
printf 'resolved\n' > "$R/g"; git -C "$R" add g; stamp git -C "$R" commit -q -m "Merge sub" -m "$A"
h=$(sha HEAD); squash feat/vil-23 "work (#1)"; pr 1 feat/vil-23 "$h" "$(sha HEAD)" "work"
run
# The merge's own change, worked out by hand: git's merge of g holds the 5 conflict lines
# (<<<, pr side, ===, sub side, >>>) and the fix keeps 1 new line, so 5 deleted + 1 added = 6.
# Counted whole (its diff from its first parent), it would be 12: b's 10 lines and g's 2.
has "the merge's own change is 6 lines" "^  [-0-9TZ:]+  [0-9a-f]{7}       6 lines  Claude Opus 5.5$"
has "...from the merge, measured as its own changes" "^      from acme/app#1 merge inside the PR \(its own changes, remerge-diff\): Merge sub"
model claude-opus-5-5 11
model qwen3-8-27b 12
label qwen3-8-27b

# --- the same repo named in two casings is searched and counted once ---------------------
case_ slug-case VIL-25 2026-02-01T00:00:00Z https://github.com/Acme/App/pull/1
repo acme/app
br -b feat/vil-25; c a 10 "work" "$A"; h=$(sha HEAD)
squash feat/vil-25 "work (#1)"; pr 1 feat/vil-25 "$h" "$(sha HEAD)" "work"
run
has "one repo line for both names" "^  acme/app  \(Linear attachment, current clone\)"
has "one PR line, found both ways" "acme/app#1  merged  found by: Linear attachment, branch "
model claude-opus-5-5 10
label claude-opus-5-5

# --- an attached PR that wasn't merged, and a local merge in a repo with no clone here ----
case_ other-repo-merge VIL-24 2026-02-01T00:00:00Z https://github.com/acme/other/pull/9
repo acme/other
br -b feat/vil-24; c a 5 "other work" "$A"; h=$(sha HEAD)
python3 -c 'import json, sys; json.dump([{"number": 9, "head_ref": "feat/vil-24", "head": sys.argv[2], "merged": False, "title": "unmerged"}], open(sys.argv[1], "w"))' "$CASE/gh/acme/other.prs.json" "$h"
br main; c m 1 "main moves on"
tick=$((tick + 1)); stamp git -C "$R" merge -q --no-ff -m "Merge feat/vil-24 (VIL-24)" -m "$B" feat/vil-24
repo acme/app
run
has "the unmerged attached PR is skipped" "acme/other#9  NOT merged, skipped"
has "the local merge's commits are counted" "^      from acme/other local merge [0-9a-f]{7} into main: other work"
has "the merge's own changes are not measured" "the merge's own changes not measured: no local clone of this repo"
model claude-opus-5-5 5
label claude-opus-5-5

# --- a commit naming two models counts for neither; the same model twice is one ---------
case_ two-models VIL-18 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-18; c a 20 "pair work" "$A"$'\n'"$B"
c b 3 "solo work" "$A"$'\n''Worker-Model: claude opus 5.5'
h=$(sha HEAD); squash feat/vil-18 "work (#1)"; pr 1 feat/vil-18 "$h" "$(sha HEAD)" "work"
run
has "the pair commit is shown as two models" "Claude Opus 5.5, qwen3.8-27b \(two or more models: credited to nobody\)"
model claude-opus-5-5 3
lacks "qwen3-8-27b gets no lines" "^  qwen3-8-27b"
nobody "two or more models" 20
label "no label: lines in commits that name no model \(20\) are more than claude-opus-5-5's \(3\)"

# --- a tie goes to the model whose newest commit is later --------------------------------
case_ tie VIL-19 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-19; c a 6 "first" "$B"; c b 10 "second" "$A"; c a 4 "third" "$B"
h=$(sha HEAD); squash feat/vil-19 "work (#1)"; pr 1 feat/vil-19 "$h" "$(sha HEAD)" "work"
run
model claude-opus-5-5 10
model qwen3-8-27b 10
label qwen3-8-27b
case_ tie-reversed VIL-19 2026-02-01T00:00:00Z
repo acme/app
br -b feat/vil-19; c a 10 "first" "$B"; c b 4 "second" "$A"; c b 6 "third" "$A"
h=$(sha HEAD); squash feat/vil-19 "work (#1)"; pr 1 feat/vil-19 "$h" "$(sha HEAD)" "work"
run
label claude-opus-5-5

# --- a local merge: its commits count without naming the id, and so does its conflict fix -
case_ local-merge VIL-20 2026-02-01T00:00:00Z
repo acme/app
c f 1 "base for the conflict"
br -b feat/vil-20-local; c b 8 "branch work, no id" "$A"
br main; c q 1 "early main work" "$B"
br feat/vil-20-local; tick=$((tick + 1))
stamp git -C "$R" merge -q --no-edit -m "Merge main into feat/vil-20-local" main
printf 'branch side\n' > "$R/f"; c - 0 "branch edits f" "$A"
br main; printf 'main side\n' > "$R/f"; c - 0 "main edits f" "$B"; c m 30 "main work, not this ticket" "$B"
tick=$((tick + 1)); stamp git -C "$R" merge -q -m x feat/vil-20-local >/dev/null 2>&1
printf 'resolved\nextra line\n' > "$R/f"; git -C "$R" add f
stamp git -C "$R" commit -q -m "Merge branch 'feat/vil-20-local' (VIL-20)" -m "$B"
run
has "the branch commit is counted from the local merge" "^      from acme/app local merge [0-9a-f]{7} into main: branch work, no id"
has "the merge's conflict fix is counted" "local merge [0-9a-f]{7} into main \(its own changes, remerge-diff\)"
has "the merge of main into the branch is skipped" "merge of main into the merged branch"
lacks "main's own work is not counted" "main work, not this ticket|early main work"
model claude-opus-5-5 10
has "qwen3-8-27b gets the conflict fix" "^  qwen3-8-27b +[1-9][0-9]* lines"
label claude-opus-5-5

# --- --no-linear, and a commit only Linear's date bound would have hidden -----------------
case_ no-linear VIL-21 2026-02-01T00:00:00Z
repo acme/app
c a 2 "direct (VIL-21)" "$A"
run --no-linear
has "says Linear wasn't read" "^Linear: not read \(--no-linear\)"
model claude-opus-5-5 2
label claude-opus-5-5

# --- nothing names a model -------------------------------------------------------------
case_ no-models VIL-22 2026-02-01T00:00:00Z
repo acme/app
c a 2 "direct (VIL-22)"
run
label "no label: no counted commit names a model"

# --- bad input -------------------------------------------------------------------------
run --repo not-a-slug
if [ "$RC" = 2 ]; then echo "ok      --repo without owner/name is a usage error"
else echo "FAIL    --repo not-a-slug: rc=$RC"; show; fail=1; fi

exit "$fail"
