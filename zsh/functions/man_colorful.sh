#!/usr/bin/env sh

# Colorful manpages
# This function is aliased to 'man' for colorful manpages by default.
man_colorful() {
    env \
        LESS_TERMCAP_mb="${LESS_TERMCAP_mb:-$(printf '\033[1;31m')}" \
        LESS_TERMCAP_md="${LESS_TERMCAP_md:-$(printf '\033[1;31m')}" \
        LESS_TERMCAP_me="${LESS_TERMCAP_me:-$(printf '\033[0m')}" \
        LESS_TERMCAP_se="${LESS_TERMCAP_se:-$(printf '\033[0m')}" \
        LESS_TERMCAP_so="${LESS_TERMCAP_so:-$(printf '\033[1;44;33m')}" \
        LESS_TERMCAP_ue="${LESS_TERMCAP_ue:-$(printf '\033[0m')}" \
        LESS_TERMCAP_us="${LESS_TERMCAP_us:-$(printf '\033[1;32m')}" \
        man "$@"
}
