#!/usr/bin/env sh

# Case-insensitive globbing (used in pathname expansion).
setopt extendedglob

# Append to the history file, rather than overwriting it.
setopt inc_append_history

# Share history with bash.
setopt share_history