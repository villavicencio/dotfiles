#!/usr/bin/env bash

# Case-insensitive globbing (used in pathname expansion).
setopt extendedglob;
unsetopt CASE_GLOB;

# Append to the history file, rather than overwriting it.
setopt inc_append_history;

# Share history with bash.
setopt share_history;
