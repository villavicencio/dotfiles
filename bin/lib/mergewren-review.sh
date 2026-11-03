# shellcheck shell=bash
# mergewren_review: wait for MergeWren's verdict on a PR's current head and print it.
# Source this file (bash or zsh), then run it from a checkout of the repo:
#   source <dotfiles clone>/bin/lib/mergewren-review.sh   # ~/Projects/Personal/dotfiles on the desk Macs
#   mergewren_review <pr> [owner/repo]
# Why it reads comments the way it does: docs/agents/code-review.md, "Merging on a MergeWren
# review". This file is the only copy; edit it here.

# Polls every MERGEWREN_POLL_S seconds (60) for up to MERGEWREN_WAIT_S (1200), re-reading the
# head each time, so a push while waiting moves it to the new head. Returns 0 and prints the
# review comment once one with a verdict exists for the current head; 1 on a GitHub error;
# 2 when none arrived in time (PENDING); 3 for a draft, which MergeWren never reviews.
mergewren_review() {
  local N=${1:-} R=${2:-} poll=${MERGEWREN_POLL_S:-60} wait=${MERGEWREN_WAIT_S:-1200} info h draft ids id body verdict now
  # $SECONDS (bash and zsh) rather than summing sleeps, so a 0 s poll still times out.
  local deadline=$((SECONDS + wait))
  [ -n "$N" ] || { echo "usage: mergewren_review <pr> [owner/repo]" >&2; return 1; }
  if [ -z "$R" ]; then
    R=$(gh repo view --json nameWithOwner -q .nameWithOwner) && [ -n "$R" ] \
      || { echo "ERROR: can't tell the repo; pass owner/repo" >&2; return 1; }
  fi
  while :; do
    info=$(gh pr view "$N" -R "$R" --json headRefOid,isDraft -q '"\(.headRefOid) \(.isDraft)"') \
      || { echo "ERROR: gh pr view $N -R $R failed" >&2; return 1; }
    h=${info% *} draft=${info#* }
    [ "$draft" = false ] || { echo "DRAFT: MergeWren skips drafts; gh pr ready $N -R $R" >&2; return 3; }
    # MergeWren posts from David's account, and its comment starts with the marker, so a
    # comment that only quotes the marker doesn't count. The REST list is paged in full.
    ids=$(gh api --paginate "repos/$R/issues/$N/comments?per_page=100" --jq ".[]
      | select(.user.login == \"villavicencio\" and (.body | startswith(\"<!-- review-stack:head=$h \")))
      | .id") || { echo "ERROR: listing PR $N's comments failed" >&2; return 1; }
    id=$(printf '%s\n' "$ids" | tail -n 1)
    if [ -n "$id" ]; then
      body=$(gh api "repos/$R/issues/comments/$id" --jq .body) \
        || { echo "ERROR: reading comment $id failed" >&2; return 1; }
      # An incremental round posts "MergeWren: no verdict — … full confirmation of <sha> queued"
      # and the full review of the same head follows, about a minute later on hal-pilot#4.
      # Only the verdict line is checked: a finding may quote that text.
      verdict=$(printf '%s\n' "$body" | grep -m 1 '^MergeWren: ')
      case $verdict in
        "MergeWren: no verdict"*) ;;
        *)
          # A push during the lookup makes this the old head's review: start over on the new one.
          now=$(gh pr view "$N" -R "$R" --json headRefOid -q .headRefOid) \
            || { echo "ERROR: gh pr view $N -R $R failed" >&2; return 1; }
          [ "$now" != "$h" ] || { printf '%s\n' "$body"; return 0; }
          continue ;;
      esac
    fi
    [ "$SECONDS" -lt "$deadline" ] || { echo "PENDING: no MergeWren verdict for ${h} after ${wait}s" >&2; return 2; }
    sleep "$poll"
  done
}
