#!/usr/bin/env sh

# List the size of all the folders and files.
alias ducks='du -cksh * | sort -rn | head -11'

# Detect which `ls` flavor is in use
if ls --color >/dev/null 2>&1; then # GNU `ls`
  colorflag="--color"
else # OS X `ls`
  colorflag="-G"
fi

# List all files colorized in long format
alias l="ls -lF ${colorflag}"

# List all files colorized in long format, including dot files
alias la="ls -laF ${colorflag}"
alias ll="la"

# List only directories
alias lsd="ls -lF ${colorflag} | grep --color=never '^d'"

# Always use color output for 'ls'
alias ls="command ls ${colorflag}"

# eza (modern ls) — override the ls family when installed. Defined after the
# plain-ls aliases above so these win when eza is present; a machine without
# eza falls back to the GNU/BSD ls aliases. Escape hatch: `\ls` or `command ls`
# always bypasses the alias for raw ls output. Aliases call eza directly (not
# the `ls` alias) to avoid recursive ls-flag leakage into eza.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias l='eza -lh --git --group-directories-first'   # long, human sizes, git
  alias ll='eza -lh --git --group-directories-first'  # alias of l
  alias la='eza -lah --git --group-directories-first' # + dotfiles
  alias lsd='eza -lhD --git'                           # long listing, dirs only
  alias lt='eza --tree --level=2 --git'                # 2-level tree
fi

# Enable aliases to be sudo’ed
alias sudo='sudo '

# Always enable colored `grep` output.
alias grep='grep --color=auto'

# Get week number
alias week='date +%V'

# Stopwatch
alias timer='echo "Timer started. Stop with Ctrl-D." && date && time cat && date'

# Update everything via topgrade
alias update='topgrade'

# Local IP address
alias localip="ipconfig getifaddr en0"

# Flush Directory Service cache
alias flush="dscacheutil -flushcache && killall -HUP mDNSResponder"

# Canonical hex dump; some systems have this symlinked
command -v hd >/dev/null || alias hd="hexdump -C"

# OS X has no `md5sum`, so use `md5` as a fallback
command -v md5sum >/dev/null || alias md5sum="md5"

# OS X has no `sha1sum`, so use `shasum` as a fallback
command -v sha1sum >/dev/null || alias sha1sum="shasum"

# Trim new lines and copy to clipboard
alias c="tr -d '\n' | pbcopy"

# Recursively delete `.DS_Store` files
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

# Show/hide hidden files in Finder
alias show="defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder"
alias hide="defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder"

# Hide/show all desktop icons (useful when presenting)
alias hidedesktop="defaults write com.apple.finder CreateDesktop -bool false && killall Finder"
alias showdesktop="defaults write com.apple.finder CreateDesktop -bool true && killall Finder"

# URL-encode strings
alias urlencode='python3 -c "import sys, urllib.parse as ul; print(ul.quote_plus(sys.argv[1]));"'

# PlistBuddy alias, because sometimes `defaults` just doesn’t cut it
alias plistbuddy="/usr/libexec/PlistBuddy"

# Reload the shell (i.e. invoke as a login shell)
alias reload="exec $SHELL -l"

# `hh` (history search) now lives in zsh/functions/hh.sh — atuin-backed, mirrors ^R.

# Alias for NVIM
if type nvim >/dev/null 2>&1; then
  alias vim='nvim'
  alias vi='vim'
fi

# Set shortcuts for some custom functions
alias fs='size_of_file_or_directory'
alias man='man_colorful'
alias mkd='mkdir_and_cd'
alias tgz='tar_and_gzip'
