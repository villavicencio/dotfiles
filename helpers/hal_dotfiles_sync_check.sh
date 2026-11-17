#!/usr/bin/env bash
#
# hal_dotfiles_sync_check.sh — Atlas's hourly dotfiles check on hal (VIL-700). Installed as
# ~/.hermes/scripts/dotfiles-sync-check.sh in `hal`'s home by
# `helpers/hal_shared_clone.sh sync-check`, and run there as `hal` by the Hermes cron job
# 637debb93470 (no agent). It is a copy, not a link: a link would point into the clone this
# script watches, and Hermes refuses a script that resolves outside ~/.hermes/scripts.
#
# Hermes runs it with whichever `bash` is first on its PATH (so it must work in macOS's bash
# 3.2), delivers its stdout to David as it is, stays silent on empty stdout, and sends an
# error alert on a non-zero exit.
#
# It watches the clone that `hal`'s ~/.config/zsh/.zshrc link points into, and never runs git
# in it: it reads the clone's .git/HEAD and refs as files, keeps its own bare copy of GitHub's
# master in `hal`'s home, and runs git only there, with no global or system git config
# (`hal`'s ~/.gitconfig is a link into the clone it watches). It prints a report when:
#   - the clone is behind GitHub's master, or on a commit that isn't on master;
#   - a tracked file outside submodules differs from the repo at the commit the clone is on
#     (at master, when that commit isn't on master), in content or executable bit, or is
#     missing, unreadable, or a link where the repo has a file (the tamper alarm);
#   - the clone holds files outside .git and submodules that that commit doesn't;
#   - this installed copy differs from master's helpers/hal_dotfiles_sync_check.sh.
# It doesn't print a report identical to the last one it recorded in its state file.
#
# Exit 0, with or without a report. Exit 1 when it can't check or can't write its state file;
# its last line says why. DOTFILES_DRY_RUN=1 fetches nothing and writes no state.
#
# Overrides, for ci/hal-shared-clone-checks.sh and by-hand runs: DOTFILES_CLONE (the clone to
# watch), DOTFILES_SYNC_REMOTE (GitHub's URL), DOTFILES_SYNC_MIRROR (the bare copy),
# DOTFILES_SYNC_STATE (the file that remembers the last report; point it at an empty file to
# see the full report without changing what Atlas has sent). The state file's default sits in
# ${HERMES_HOME:-~/.hermes}/scripts, as Hermes itself reads HERMES_HOME.
# The backticks in single quotes are Slack formatting, not command substitution.
# shellcheck disable=SC2016
set -u

# Tools from the system only: nothing on this PATH comes from the watched clone or Homebrew.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH LC_ALL=C
GIT=/usr/bin/git
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REMOTE=${DOTFILES_SYNC_REMOTE:-https://github.com/villavicencio/dotfiles.git}
MIRROR=${DOTFILES_SYNC_MIRROR:-$HOME/.cache/dotfiles-sync-check/master.git}
STATE=${DOTFILES_SYNC_STATE:-${HERMES_HOME:-$HOME/.hermes}/scripts/.dotfiles-sync-check.state}
SELF_PATH=helpers/hal_dotfiles_sync_check.sh
MAX=10
DRY=${DOTFILES_DRY_RUN:-0}

fail() { echo "dotfiles-sync-check: $*"; exit 1; }
G() { "$GIT" --git-dir="$MIRROR" -c gc.autoDetach=false "$@"; }

zrc=$(readlink "$HOME/.config/zsh/.zshrc" 2>/dev/null)
CLONE=${DOTFILES_CLONE:-${zrc%/zsh/zshrc}}
[ -n "$CLONE" ] || fail "can't find the dotfiles clone (no ~/.config/zsh/.zshrc link; set DOTFILES_CLONE)"
[ -r "$CLONE/.git/HEAD" ] || fail "can't read $CLONE/.git/HEAD as $(id -un) (is the clone there, and the ACL on its owner's home in place?)"

# The commit the clone is on, read from its files: HEAD, then the loose ref or packed-refs.
h=$(head -n 1 "$CLONE/.git/HEAD")
case $h in
  "ref: refs/heads/"*)
    ref=${h#ref: }; branch=${ref#refs/heads/}
    if [ -f "$CLONE/.git/$ref" ]; then
      head=$(head -n 1 "$CLONE/.git/$ref")
    else
      head=$(awk -v r="$ref" '$2 == r { print $1; exit }' "$CLONE/.git/packed-refs" 2>/dev/null)
    fi ;;
  *) head=$h; branch=detached ;;
esac
[[ $head =~ ^[0-9a-f]{40}$ ]] || fail "can't tell which commit $CLONE is on (HEAD: $h)"

if [ "$DRY" = 1 ] && [ ! -f "$MIRROR/HEAD" ]; then
  echo "[dry-run] $CLONE is on $branch at ${head:0:7}. Would create $MIRROR, fetch GitHub's master into it, and compare. Nothing changed."
  exit 0
fi

TMP=$(mktemp -d) || fail "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

if [ "$DRY" != 1 ]; then
  if [ ! -f "$MIRROR/HEAD" ]; then
    if ! { mkdir -p "$MIRROR" && G init -q --bare; }; then fail "can't create $MIRROR"; fi
  fi
  G fetch -q --no-tags "$REMOTE" "+refs/heads/master:refs/heads/master" 2>"$TMP/err" ||
    fail "fetch of GitHub's master failed: $(head -n 1 "$TMP/err")"
fi
origin=$(G rev-parse -q --verify "refs/heads/master^{commit}") || fail "no master in $MIRROR after the fetch"

# Where the clone stands. A commit that isn't in the mirror isn't on GitHub's master.
# merge-base exits 1 for "not an ancestor"; anything else is a failure, not an answer.
behind=0 onmaster=1
if [ "$head" != "$origin" ]; then
  if ! G cat-file -e "$head^{commit}" 2>/dev/null; then
    onmaster=0
  else
    G merge-base --is-ancestor "$head" "$origin"; rc=$?
    case $rc in
      0) behind=$(G rev-list --count "$head..$origin") || fail "can't count the commits between ${head:0:7} and ${origin:0:7}" ;;
      1) onmaster=0 ;;
      *) fail "git merge-base failed in $MIRROR (exit $rc)" ;;
    esac
  fi
fi
base=$head; [ "$onmaster" = 1 ] || base=$origin

# Tamper check: every entry of base's tree against the clone's file at that path. Each
# command's own exit is checked, so a failed step can't read as "no difference" (the one
# pipeline, for a link's target, fails toward "differs").
WFAIL=0
add() { { printf '%s\n' "$2" >> "$TMP/$1"; } 2>/dev/null || WFAIL=1; }
for x in tracked paths want subs bad regular exec.want; do
  { : > "$TMP/$x"; } 2>/dev/null || WFAIL=1
done
G ls-tree -r -z --full-tree "$base" > "$TMP/tree" || fail "can't list the tree of ${base:0:7}"
while IFS= read -r -d '' rec; do
  meta=${rec%%$'\t'*} p=${rec#*$'\t'}
  mode=${meta%% *} sha=${meta##* }
  f=$CLONE/$p
  # A path with a newline would break the line-based files below: one line, the newline shown as ?.
  case $p in *$'\n'*) p=${p//$'\n'/?}; add tracked "$p"; add bad "odd path"$'\t'"$p"; continue ;; esac
  add tracked "$p"
  case $mode in
    160000) add subs "$p" ;;
    120000)
      # readlink -n gives the target's exact bytes (no command substitution to strip newlines).
      if [ ! -L "$f" ] || [ "$(readlink -n "$f" | G hash-object --stdin)" != "$sha" ]; then
        add bad "differs"$'\t'"$p"
      fi ;;
    *)
      if [ -L "$f" ]; then add bad "is a link"$'\t'"$p"
      elif [ ! -e "$f" ]; then add bad "missing"$'\t'"$p"
      elif [ ! -f "$f" ] || [ ! -r "$f" ]; then add bad "unreadable"$'\t'"$p"
      else add paths "$f"; add want "$sha"$'\t'"$p"; add regular "$p"
        [ "$mode" != 100755 ] || add exec.want "$p"
      fi ;;
  esac
done < "$TMP/tree"
[ "$WFAIL" = 0 ] || fail "couldn't write its temp files (disk full?)"
if [ -s "$TMP/paths" ]; then
  G hash-object --no-filters --stdin-paths < "$TMP/paths" > "$TMP/got" || fail "can't hash the files in $CLONE"
  { n=$(wc -l < "$TMP/paths") && g=$(wc -l < "$TMP/got") && w=$(wc -l < "$TMP/want") &&
    [ "$g" -eq "$n" ] && [ "$w" -eq "$n" ]; } 2>/dev/null || fail "couldn't hash every file in $CLONE"
  { paste "$TMP/got" "$TMP/want" > "$TMP/pairs" &&
    awk -F'\t' '$1 != $2 { print "differs\t" $3 }' "$TMP/pairs" >> "$TMP/bad"; } ||
    fail "couldn't compare the file hashes"
fi

# The executable bit, as git sees it (the owner's x): for each tracked file, it must match
# the tree's mode, 100755 or 100644.
(cd "$CLONE" && find . -path ./.git -prune -o -type f -perm -0100 -print) > "$TMP/exec.raw" 2> "$TMP/err" ||
  fail "can't list the executable files in $CLONE: $(head -n 1 "$TMP/err")"
{ sed 's|^\./||' "$TMP/exec.raw" > "$TMP/exec.rel" &&
  sort "$TMP/exec.rel" > "$TMP/exec.have" &&
  sort "$TMP/regular" > "$TMP/regular.sorted" &&
  sort "$TMP/exec.want" > "$TMP/exec.want.sorted" &&
  comm -12 "$TMP/regular.sorted" "$TMP/exec.have" > "$TMP/exec.tracked" &&
  comm -3 "$TMP/exec.want.sorted" "$TMP/exec.tracked" > "$TMP/exec.diff" &&
  sed 's/^\t//; s/^/mode\t/' "$TMP/exec.diff" >> "$TMP/bad"; } ||
  fail "couldn't compare the executable bits"

# Files in the clone that base doesn't have. Submodule folders and .git are skipped. A folder
# it can't read is "can't tell", so it stops rather than report nothing.
(cd "$CLONE" && find . -path ./.git -prune -o \( -type f -o -type l \) -print) > "$TMP/found.raw" 2> "$TMP/err" ||
  fail "can't list every file in $CLONE: $(head -n 1 "$TMP/err")"
{ sed 's|^\./||' "$TMP/found.raw" > "$TMP/found.rel" &&
  awk -v sf="$TMP/subs" 'BEGIN { while ((getline l < sf) > 0) s[l] = 1 } { for (d in s) if (index($0, d "/") == 1) next; print }' "$TMP/found.rel" > "$TMP/found.nosub" &&
  sort "$TMP/found.nosub" > "$TMP/found" &&
  sort "$TMP/tracked" > "$TMP/tracked.sorted" &&
  comm -23 "$TMP/found" "$TMP/tracked.sorted" > "$TMP/extra"; } || fail "couldn't compare the clone's files with the tree"

# Is this installed copy master's?
self=${BASH_SOURCE[0]:-$0}
self_ok=1
want_self=$(G rev-parse -q --verify "$origin:$SELF_PATH" 2>/dev/null)
if [ -z "$want_self" ] || [ "$(G hash-object --no-filters -- "$self" 2>/dev/null)" != "$want_self" ]; then self_ok=0; fi

# list <label> <file>: one bullet naming up to $MAX paths from the file's lines; fails when awk does.
list() {
  [ -s "$2" ] || return 0
  awk -v label="$1" -v max="$MAX" '{ n++; if (n <= max) s = s (n > 1 ? ", " : "") "`" $0 "`" }
    END { printf "• %s (%d): %s", label, n, s; if (n > max) printf " and %d more", n - max; printf "\n" }' "$2"
}

report() {
  local owner pull
  owner=$(stat -f %Su "$CLONE" 2>/dev/null) || owner=''
  if [ "$owner" = "$(id -un)" ]; then
    pull="ssh hal-as-hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'"
  else
    pull="ssh hal 'git -C ~/Projects/Personal/dotfiles pull --ff-only'"
  fi
  echo "*dotfiles on hal doesn't match GitHub's master* (\`${origin:0:7}\`)"
  echo "• clone: \`$CLONE\` (\`${owner:-?}\`'s), on \`$branch\` at \`${head:0:7}\`"
  if [ "$onmaster" = 0 ]; then
    echo "• that commit isn't on master, so the files below are compared with master itself"
  elif [ "$behind" -gt 0 ]; then
    echo "• $behind commit(s) behind; from the Mac: \`$pull\`"
  fi
  local k at=${base:0:7}
  for k in differs mode missing unreadable 'is a link' 'odd path'; do
    awk -F'\t' -v k="$k" '$1 == k { print $2 }' "$TMP/bad" > "$TMP/k" || return 1
    case $k in
      differs) list "*differ from $at*" "$TMP/k" ;;
      mode) list "*executable bit differs from $at*" "$TMP/k" ;;
      *) list "*$k*" "$TMP/k" ;;
    esac || return 1
  done
  list "*not in $at*" "$TMP/extra" || return 1
  if [ -s "$TMP/bad" ] || [ -s "$TMP/extra" ]; then
    echo "    \`hal\` runs these files. Look before pulling, as \`${owner:-the clone owner}\`: \`git -C $CLONE status --short\`"
  fi
  if [ "$self_ok" = 0 ]; then
    echo "• this check isn't master's \`$SELF_PATH\`: once \`david\`'s clone is on master, from the Mac: \`ssh hal-as-hal 'bash ~david/Projects/Personal/dotfiles/helpers/hal_shared_clone.sh sync-check'\`"
  fi
  if [ "$onmaster" = 1 ] && [ "$behind" -gt 0 ]; then
    echo "New on master:"
    G log --no-decorate --format='    • `%h` %s' "$head..$origin" > "$TMP/log" || return 1
    head -n "$MAX" "$TMP/log" || return 1
  fi
}

insync=0
[ "$behind" = 0 ] && [ "$onmaster" = 1 ] && [ ! -s "$TMP/bad" ] && [ ! -s "$TMP/extra" ] && [ "$self_ok" = 1 ] && insync=1
if [ "$DRY" = 1 ]; then
  echo "[dry-run] compared with the master already in $MIRROR (${origin:0:7}, not fetched); no state written:"
  if [ "$insync" = 1 ]; then echo "in sync"; else report || fail "couldn't build its report"; fi
  exit 0
fi
# The state file decides what counts as already reported, so a write that fails is an error:
# a stale state could otherwise silence the next report.
if [ "$insync" = 1 ]; then
  { printf 'in sync %s\n' "$origin" > "$STATE"; } 2>/dev/null ||
    fail "in sync, but couldn't write $STATE, so a later report could be silenced"
  exit 0
fi
{ report > "$TMP/report" && [ -s "$TMP/report" ]; } || fail "couldn't build its report"
key=$(shasum -a 256 < "$TMP/report" | cut -d' ' -f1)
[[ $key =~ ^[0-9a-f]{64}$ ]] || fail "couldn't hash its report"
[ "$key" = "$(cat "$STATE" 2>/dev/null)" ] && exit 0
cat "$TMP/report" || fail "couldn't print its report"
if ! { printf '%s\n' "$key" > "$STATE"; } 2>/dev/null; then
  echo "dotfiles-sync-check: couldn't write $STATE, so this report will repeat"
  exit 1
fi
exit 0
