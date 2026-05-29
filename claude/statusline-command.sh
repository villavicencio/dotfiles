#!/bin/sh
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
# Reasoning effort level from /effort (low|medium|high|xhigh|max|ultra). Absent
# when the active model doesn't support the effort parameter. Field path is
# documented at code.claude.com/docs/en/statusline.md (.effort.level).
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Accent colors for the model section (truecolor; ASCII + octal \033 only, so
# POSIX/dash-safe). Effort is bold violet (live status, draws the eye); the
# parenthetical descriptor (e.g. "1M context") is a softer non-bold gold —
# warm against the cyan dir + violet effort, distinct from the green ctx.
effort_color="\033[1;38;2;165;110;255m"
descriptor_color="\033[38;2;205;170;100m"

# Shorten home directory to ~
# POSIX prefix substitution (works in dash AND bash). The bash-only
# form `${cwd/#$home/~}` triggers "Bad substitution" under dash, which
# is /bin/sh on Linux — settings.json invokes this script via `sh`.
home="$HOME"
case "$cwd" in
  "$home")   short_cwd="~" ;;
  "$home"/*) short_cwd="~${cwd#"$home"}" ;;
  *)         short_cwd="$cwd" ;;
esac

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

    # Turn the branch name into an OSC 8 terminal hyperlink to the branch on
    # GitHub. The URL is parsed from origin with pure string ops (no network),
    # so the statusline stays fast. Handles scp-form (git@host:owner/repo),
    # https://, ssh://, SSH host aliases (e.g. github-work), and strips any
    # embedded credentials. Only GitHub remotes are linked; anything else (or
    # no origin) falls back to a plain, unlinked name.
    # NOTE: Claude Code documents OSC 8 support, but links can be non-clickable
    # inside tmux on some versions (upstream issues #27047 / #23438). BEL (\007)
    # terminator is used for best tmux passthrough. If it ever renders garbled,
    # clear branch_url below to fall back to a plain name.
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

    # U+E0A0 (Powerline branch glyph) — UTF-8 octal \356\202\240 (POSIX printf;
    # \xHH/\uXXXX are NOT POSIX — dash on Linux prints them literally; literal
    # PUA chars are also stripped by the Claude Code Write tool — see
    # docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md).
    printf " \033[2m|\033[0m ${branch_color}\356\202\240 "
    if [ -n "$branch_url" ]; then
      printf '\033]8;;%s\007%s\033]8;;\007' "$branch_url" "$branch"
    else
      printf '%s' "$branch"
    fi
    printf "\033[0m"
  fi
fi

if [ -n "$model" ]; then
  printf " \033[2m|\033[0m "
  case "$model" in
    *"("*)
      # Display name carries a parenthetical descriptor, e.g.
      # "Opus 4.8 (1M context)". Split into base + inner; color the descriptor
      # gold and, if effort is set, append it in violet inside the same parens
      # -> "Opus 4.8 (1M context, xhigh)".
      mbase=${model%)}        # drop trailing ")":           "Opus 4.8 (1M context"
      minner=${mbase#*(}      # text inside the parens:      "1M context"
      mbase=${mbase%%(*}      # text before "(" (keeps space):"Opus 4.8 "
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
