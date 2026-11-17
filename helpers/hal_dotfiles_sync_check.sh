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
# It watches the clone that `hal`'s ~/.config/zsh/.zshrc link points into: `david`'s clone once
# `hal`'s links have been moved there, `hal`'s own before that. It never runs git in that
# clone. It reads the clone's .git/HEAD and refs as plain files, keeps its own bare copy of
# GitHub's master in `hal`'s home, and runs git only there, with no global or system git
# config (`hal`'s ~/.gitconfig is a link into the clone it watches). It prints a report when:
#   - the clone is behind GitHub's master, or on a commit that isn't on master;
#   - a tracked file in the clone differs from GitHub's copy of it at the commit the clone is
#     on (or at master, when that commit isn't on master), is missing, is unreadable, or is a
#     link where the repo has a file. This is the tamper alarm: `hal` runs these files, and
#     `david`, or anything running as `david`, can change them;
#   - the clone holds files that commit doesn't (outside .git and submodules);
#   - this installed copy differs from master's helpers/hal_dotfiles_sync_check.sh.
# Each report is sent once; the next merge, pull or change to the clone sends a new one.
#
# Exit 0, with or without a report. Exit 1 with one line saying why when it can't check
# (clone not found, a folder in it unreadable, GitHub unreachable) or can't write its state
# file; Hermes then sends an error alert that includes whatever was printed.
#
# DOTFILES_DRY_RUN=1 fetches nothing and writes no state. It reads which commit the clone is on;
# if the bare copy already exists, it also prints the report against the master in it (or "in
# sync"). It creates nothing on hal except a temp folder it removes.
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

# Tamper check: every entry of base's tree against the clone's file at that path.
: > "$TMP/tracked"; : > "$TMP/paths"; : > "$TMP/want"; : > "$TMP/subs"; : > "$TMP/bad"
G ls-tree -r -z --full-tree "$base" > "$TMP/tree" || fail "can't list the tree of ${base:0:7}"
while IFS= read -r -d '' rec; do
  meta=${rec%%$'\t'*} p=${rec#*$'\t'}
  mode=${meta%% *} sha=${meta##* }
  f=$CLONE/$p
  printf '%s\n' "$p" >> "$TMP/tracked"
  case $p in *$'\n'*) printf 'odd path\t%s\n' "$p" >> "$TMP/bad"; continue ;; esac
  case $mode in
    160000) printf '%s\n' "$p" >> "$TMP/subs" ;;
    120000)
      if [ ! -L "$f" ] || [ "$(printf '%s' "$(readlink "$f")" | G hash-object --stdin)" != "$sha" ]; then
        printf 'differs\t%s\n' "$p" >> "$TMP/bad"
      fi ;;
    *)
      if [ -L "$f" ]; then printf 'is a link\t%s\n' "$p" >> "$TMP/bad"
      elif [ ! -e "$f" ]; then printf 'missing\t%s\n' "$p" >> "$TMP/bad"
      elif [ ! -f "$f" ] || [ ! -r "$f" ]; then printf 'unreadable\t%s\n' "$p" >> "$TMP/bad"
      else printf '%s\n' "$f" >> "$TMP/paths"; printf '%s\t%s\n' "$sha" "$p" >> "$TMP/want"
      fi ;;
  esac
done < "$TMP/tree"
# Every tree entry must have been written down, or a failed write could hide a finding.
n_tree=$(tr -cd '\0' < "$TMP/tree" | wc -c | tr -d ' ')
[ "$(wc -l < "$TMP/tracked" | tr -d ' ')" = "$n_tree" ] || fail "couldn't write its temp files (disk full?)"
if [ -s "$TMP/paths" ]; then
  G hash-object --no-filters --stdin-paths < "$TMP/paths" > "$TMP/got" || fail "can't hash the files in $CLONE"
  n=$(wc -l < "$TMP/paths" | tr -d ' ')
  [ "$(wc -l < "$TMP/got" | tr -d ' ')" = "$n" ] && [ "$(wc -l < "$TMP/want" | tr -d ' ')" = "$n" ] ||
    fail "couldn't write its temp files (disk full?)"
  paste "$TMP/got" "$TMP/want" | awk -F'\t' '$1 != $2 { print "differs\t" $3 }' >> "$TMP/bad" ||
    fail "couldn't write its temp files (disk full?)"
fi

# Files in the clone that base doesn't have. Submodule folders and .git are skipped. A folder
# it can't read is "can't tell", so it stops rather than report nothing.
(cd "$CLONE" && find . -path ./.git -prune -o \( -type f -o -type l \) -print) > "$TMP/found.raw" 2> "$TMP/err" ||
  fail "can't list every file in $CLONE: $(head -n 1 "$TMP/err")"
{ sed 's|^\./||' "$TMP/found.raw" |
    awk -v sf="$TMP/subs" 'BEGIN { while ((getline l < sf) > 0) s[l] = 1 } { for (d in s) if (index($0, d "/") == 1) next; print }' |
    sort > "$TMP/found" &&
  sort "$TMP/tracked" > "$TMP/tracked.sorted" &&
  comm -23 "$TMP/found" "$TMP/tracked.sorted" > "$TMP/extra"; } || fail "couldn't write its temp files (disk full?)"

# Is this installed copy master's?
self=${BASH_SOURCE[0]:-$0}
self_ok=1
want_self=$(G rev-parse -q --verify "$origin:$SELF_PATH" 2>/dev/null)
if [ -z "$want_self" ] || [ "$(G hash-object --no-filters -- "$self" 2>/dev/null)" != "$want_self" ]; then self_ok=0; fi

# list <label> <file>: one bullet naming up to $MAX paths from the file's lines.
list() {
  local n
  n=$(wc -l < "$2" | tr -d ' ')
  [ "$n" -gt 0 ] || return 0
  printf '• %s (%s): %s' "$1" "$n" "$(head -n "$MAX" "$2" | sed 's/.*/`&`/' | paste -sd ',' - | sed 's/,/, /g')"
  [ "$n" -le "$MAX" ] || printf ' and %s more' $((n - MAX))
  printf '\n'
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
  local k
  for k in differs missing unreadable 'is a link' 'odd path'; do
    awk -F'\t' -v k="$k" '$1 == k { print $2 }' "$TMP/bad" > "$TMP/k"
    case $k in
      differs) list "*differ from master*" "$TMP/k" ;;
      *) list "*$k*" "$TMP/k" ;;
    esac
  done
  list "*not on master*" "$TMP/extra"
  if [ -s "$TMP/bad" ] || [ -s "$TMP/extra" ]; then
    echo "    \`hal\` runs these files. Look before pulling, as \`${owner:-the clone owner}\`: \`git -C $CLONE status --short\`"
  fi
  if [ "$self_ok" = 0 ]; then
    echo "• this check isn't master's \`$SELF_PATH\`: after the pull, run \`helpers/hal_shared_clone.sh sync-check\` as \`hal\`"
  fi
  if [ "$onmaster" = 1 ] && [ "$behind" -gt 0 ]; then
    echo "New on master:"
    G log --no-decorate --format='    • `%h` %s' "$head..$origin" > "$TMP/log" || return 1
    head -n "$MAX" "$TMP/log"
    G diff --name-only "$head" "$origin" > "$TMP/diff" || return 1
    if grep -qE '^(dotbot-conf/|brew/|helpers/|install$)' "$TMP/diff"; then
      echo "Install files changed. \`hal\`'s server install from a clone \`david\` owns is VIL-736; see \"One dotfiles clone on hal\" in docs/reference/install-and-server.md."
    fi
  fi
}

insync=0
[ "$behind" = 0 ] && [ "$onmaster" = 1 ] && [ ! -s "$TMP/bad" ] && [ ! -s "$TMP/extra" ] && [ "$self_ok" = 1 ] && insync=1
if [ "$DRY" = 1 ]; then
  echo "[dry-run] compared with the master already in $MIRROR (${origin:0:7}, not fetched); no state written:"
  if [ "$insync" = 1 ]; then echo "in sync"; else report || fail "couldn't build its report (git log or diff failed)"; fi
  exit 0
fi
# The state file decides what counts as already reported, so a write that fails is an error:
# a stale state could otherwise silence the next report.
if [ "$insync" = 1 ]; then
  printf 'in sync %s\n' "$origin" > "$STATE" 2>/dev/null ||
    fail "in sync, but couldn't write $STATE, so a later report could be silenced"
  exit 0
fi
{ report > "$TMP/report" && [ -s "$TMP/report" ]; } || fail "couldn't build its report (git log or diff failed, or the disk is full)"
key=$(shasum -a 256 < "$TMP/report" | cut -d' ' -f1)
[[ $key =~ ^[0-9a-f]{64}$ ]] || fail "couldn't hash its report"
[ "$key" = "$(cat "$STATE" 2>/dev/null)" ] && exit 0
cat "$TMP/report" || fail "couldn't print its report"
if ! printf '%s\n' "$key" > "$STATE" 2>/dev/null; then
  echo "dotfiles-sync-check: couldn't write $STATE, so this report will repeat"
  exit 1
fi
exit 0
