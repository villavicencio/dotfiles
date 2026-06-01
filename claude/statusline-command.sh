#!/bin/sh
input=$(cat)

# Parse every field in ONE jq pass (one fork, not one per field). Fields are
# joined with US (0x1F, a non-whitespace control char) so empty values survive
# the read — a tab delimiter would collapse adjacent empties because tab is
# IFS-whitespace. map(tostring) is null-safe here only because every selector
# below carries a // "" or // 0 default, so the array holds no nulls.
US=$(printf '\037')
IFS="$US" read -r cwd model used effort la lr lim5 lim7 pr_num pr_state pr_url wt <<EOF
$(echo "$input" | jq -r '[
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.context_window.used_percentage // ""),
  (.effort.level // ""),
  (.cost.total_lines_added // 0),
  (.cost.total_lines_removed // 0),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.pr.number // ""),
  (.pr.review_state // ""),
  (.pr.url // ""),
  (.worktree.name // .workspace.git_worktree // "")
] | map(tostring) | join("\u001f")')
EOF

# Accent colors (truecolor; ASCII + octal \033 only, so POSIX/dash-safe). The
# parenthetical descriptor (e.g. "1M", "context" stripped) and the effort level
# share one soft gold — warm against the cyan dir, distinct from the green ctx;
# the whole "(1M, xhigh)" group reads as a single accent.
effort_color="\033[38;2;205;170;100m"
descriptor_color="\033[38;2;205;170;100m"
# Worktree badge: bold amber so an isolated checkout is impossible to miss.
wt_color="\033[1;38;2;235;140;60m"
# PR badge: violet, distinct from the magenta working-branch name.
pr_color="\033[38;2;170;130;255m"

# Color a 0-100 meter: green < 50, amber < 80, red >= 80.
meter_color() {
  if [ "$1" -ge 80 ]; then printf '\033[31m'
  elif [ "$1" -ge 50 ]; then printf '\033[33m'
  else printf '\033[32m'
  fi
}

# Shorten home directory to ~  (POSIX prefix substitution; works in dash AND
# bash — the bash-only form ${cwd/#$home/~} triggers "Bad substitution" under
# dash, which is /bin/sh and how settings.json invokes this script).
home="$HOME"
case "$cwd" in
  "$home")   short_cwd="~" ;;
  "$home"/*) short_cwd="~${cwd#"$home"}" ;;
  *)         short_cwd="$cwd" ;;
esac

# Cyan directory.
printf "\033[36m%s\033[0m" "$short_cwd"

# Repo cluster: worktree badge, git branch (linked), session line-delta, PR
# badge. Rendered as one " | " segment; skipped entirely outside a repo.
branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
fi
if [ -n "$branch" ] || [ -n "$wt" ] || [ -n "$pr_num" ]; then
  printf " \033[2m|\033[0m "

  # Worktree badge (fork glyph U+F126 -> octal \357\204\246). Sourced from the
  # session JSON, not git, so it shows even on a detached-HEAD worktree.
  if [ -n "$wt" ]; then
    printf "${wt_color}\357\204\246 %s\033[0m " "$wt"
  fi

  if [ -n "$branch" ]; then
    # master/main render dim (default-branch, low weight); any other branch
    # renders magenta so the working-branch name pops.
    case "$branch" in
      master|main) branch_color="\033[2m\033[37m" ;;
      *)           branch_color="\033[35m" ;;
    esac

    # OSC 8 hyperlink to the branch on GitHub, parsed from origin with pure
    # string ops (no network). Handles scp-form (git@host:owner/repo), https://,
    # ssh://, SSH host aliases (e.g. github-work), and strips embedded
    # credentials. Non-GitHub remote / no origin -> plain, unlinked name.
    # NOTE: links can be non-clickable inside tmux on some versions (upstream
    # #27047 / #23438); BEL (\007) terminator gives best tmux passthrough. If it
    # ever renders garbled, clear branch_url to fall back to a plain name.
    branch_url=""
    remote=$(git -C "$cwd" remote get-url origin 2>/dev/null)
    if [ -n "$remote" ]; then
      r=${remote%.git}
      case "$r" in *://*) r=${r#*://} ;; esac   # strip scheme
      r=${r#*@}                                  # strip user[:token]@
      case "${r%%[:/]*}" in                      # host (or SSH alias)
        *github*) branch_url="https://github.com/${r#*[:/]}/tree/${branch}" ;;
      esac
    fi

    # U+E0A0 (Powerline branch glyph) as octal \356\202\240 (\xHH/\uXXXX are NOT
    # POSIX — dash prints them literally; literal PUA chars are also stripped by
    # the Claude Code Write tool — see
    # docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md).
    # shellcheck disable=SC2059  # color vars hold \033 escapes; must sit in the format to interpret
    printf "${branch_color}\356\202\240 "
    if [ -n "$branch_url" ]; then
      printf '\033]8;;%s\007%s\033]8;;\007' "$branch_url" "$branch"
    else
      printf '%s' "$branch"
    fi
    printf "\033[0m"

    # Session line-delta in parens next to the branch; hidden until something
    # changes (both counts 0). Added green, removed red.
    if [ "$la" != 0 ] || [ "$lr" != 0 ]; then
      printf " \033[2m(\033[0m\033[32m+%s\033[0m\033[2m/\033[0m\033[31m-%s\033[0m\033[2m)\033[0m" "$la" "$lr"
    fi
  fi

  # PR badge (git-pull-request glyph U+F407 -> octal \357\220\207), OSC 8-linked
  # to the PR. Present only while an open PR is found for the branch.
  if [ -n "$pr_num" ]; then
    # shellcheck disable=SC2059  # color vars hold \033 escapes; must sit in the format to interpret
    printf " ${pr_color}\357\220\207 "
    if [ -n "$pr_url" ]; then
      printf '\033]8;;%s\007#%s\033]8;;\007' "$pr_url" "$pr_num"
    else
      printf '#%s' "$pr_num"
    fi
    printf "\033[0m"
    # review_state: approved green, changes_requested red, pending amber, else dim.
    if [ -n "$pr_state" ]; then
      case "$pr_state" in
        approved)          ps_color="\033[32m" ;;
        changes_requested) ps_color="\033[31m" ;;
        pending)           ps_color="\033[33m" ;;
        *)                 ps_color="\033[2m\033[37m" ;;
      esac
      printf " ${ps_color}%s\033[0m" "$pr_state"
    fi
  fi
fi

# Model + descriptor + effort.
if [ -n "$model" ]; then
  printf " \033[2m|\033[0m "
  case "$model" in
    *"("*)
      # "Opus 4.8 (1M context)" -> base + inner; strip the implied " context",
      # gold the descriptor, append effort in the same gold -> "(1M, xhigh)".
      mbase=${model%)}          # drop trailing ")":            "Opus 4.8 (1M context"
      minner=${mbase#*(}        # text inside the parens:       "1M context"
      minner=${minner% context} # "context" is implied; drop it: "1M"
      mbase=${mbase%%(*}        # text before "(" (keeps space): "Opus 4.8 "
      printf "\033[37m%s(\033[0m" "$mbase"
      printf "${descriptor_color}%s\033[0m" "$minner"
      if [ -n "$effort" ]; then
        printf "\033[37m, \033[0m"
        printf "${effort_color}%s\033[0m" "$effort"
      fi
      printf "\033[37m)\033[0m"
      ;;
    *)
      # No parenthetical in the display name. Give effort its own parens
      # -> "Sonnet 4.6 (high)".
      if [ -n "$effort" ]; then
        printf "\033[37m%s (\033[0m" "$model"
        printf "${effort_color}%s\033[0m" "$effort"
        printf "\033[37m)\033[0m"
      else
        printf "\033[37m%s\033[0m" "$model"
      fi
      ;;
  esac
fi

# Meters: context window, then 5h / 7d rate-limit windows (Claude.ai subs only;
# absent on Vertex). One " | " segment, space-separated.
if [ -n "$used" ] || [ -n "$lim5" ] || [ -n "$lim7" ]; then
  printf " \033[2m|\033[0m "
  sep=""
  if [ -n "$used" ]; then
    u=$(printf "%.0f" "$used"); c=$(meter_color "$u")
    printf "%s%sctx:%d%%\033[0m" "$sep" "$c" "$u"; sep=" "
  fi
  if [ -n "$lim5" ]; then
    v=$(printf "%.0f" "$lim5"); c=$(meter_color "$v")
    printf "%s%s5h:%d%%\033[0m" "$sep" "$c" "$v"; sep=" "
  fi
  if [ -n "$lim7" ]; then
    v=$(printf "%.0f" "$lim7"); c=$(meter_color "$v")
    printf "%s%s7d:%d%%\033[0m" "$sep" "$c" "$v"; sep=" "
  fi
fi
