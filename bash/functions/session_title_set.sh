#!/usr/bin/env bash
# shellcheck disable=SC2001

# Set the terminal tab title.
function session_title_set() {
    if [ $# -eq 0 ]
        then
        eval set -- "\\u@\\h: \\w"
    fi

    case $TERM in
        xterm*) local title="\[\033]0;$*\007\]";;
        *) local title=''
    esac

    prompt=$(echo "$PS1" | sed -e 's/\\\[\\033\]0;.*\\007\\\]//')

    local prompt
    PS1="${title}${prompt}"
}
