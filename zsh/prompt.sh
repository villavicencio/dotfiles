#!/usr/bin/env zsh
# shellcheck shell=bash

export TERM='xterm-256color'
export CLICOLOR=1
export LSCOLORS=bxFxBxDxCxegedabagacad
export HSTR_CONFIG=hicolor

# shellcheck disable=SC2154
RESET=$reset_color
# shellcheck disable=SC2016
git_info='$(git_prompt_info)${FG[009]}$(git_prompt_status)%{$RESET%}'
prompt="%(?,${FG[084]}"$'\u26A1'",${FG[009]}"$'\u2716\u2009'")"
directory_path="${FG[005]}%~"
return_code="%(?,,${FG[007]}${BG[009]}RC=%?%{$RESET%})"$'\u2009'

PROMPT="${prompt}"
PROMPT+="${directory_path}"
PROMPT+="${git_info}"
PROMPT+=$'\u2009\u279C\u2009\u2009'

RPROMPT="${return_code}"

# prompt cursor fix when exiting vim
_fix_cursor() {
  echo -ne "\e[1 q"
}
precmd_functions+=(_fix_cursor)

export ZSH_THEME_GIT_PROMPT_PREFIX="%{$RESET%}\u2009\uE0A0\u2009${FG[009]}"
export ZSH_THEME_GIT_PROMPT_SUFFIX=""
export ZSH_THEME_GIT_PROMPT_DIRTY="\u2009(\u2009"
export ZSH_THEME_GIT_PROMPT_CLEAN=""
export ZSH_THEME_GIT_PROMPT_ADDED="\u0008+\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_MODIFIED="\u0008\u2191\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_DELETED="\u0008\u2716\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_RENAMED="\u0008\u279C\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_UNMERGED="\u0008#\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_UNTRACKED="\u0008\u003F\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_STASHED="\u0008$\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_BEHIND="\u0008•|\u2009\u0008)"
export ZSH_THEME_GIT_PROMPT_AHEAD="\u0008|•\u2009\u0008)"
