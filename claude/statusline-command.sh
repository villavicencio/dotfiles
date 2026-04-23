#!/bin/sh
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/~}"

# Build status line with ANSI colors
# Cyan for directory, dim white for model, color-coded context usage
printf "\033[36m%s\033[0m" "$short_cwd"

# Git branch — hidden when not inside a repo or on detached HEAD.
# master/main render dim (default-branch, low visual weight); any other
# branch renders magenta so the working-branch name pops.
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    case "$branch" in
      master|main) branch_color="\033[2m\033[37m" ;;
      *)           branch_color="\033[35m" ;;
    esac
    # U+E0A0 (Powerline branch glyph) — encoded as UTF-8 \xee\x82\xa0 because
    # /bin/sh / bash 3.2 printf does not interpret \uXXXX. Literal PUA chars
    # in the source would also be stripped by the Claude Code Write tool (see
    # docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md).
    printf " \033[2m|\033[0m ${branch_color}\xee\x82\xa0 %s\033[0m" "$branch"
  fi
fi

if [ -n "$model" ]; then
  printf " \033[2m|\033[0m \033[37m%s\033[0m" "$model"
fi

if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  if [ "$used_int" -ge 80 ]; then
    color="\033[31m"  # red
  elif [ "$used_int" -ge 50 ]; then
    color="\033[33m"  # yellow
  else
    color="\033[32m"  # green
  fi
  printf " \033[2m|\033[0m ${color}ctx:%d%%\033[0m" "$used_int"
fi
