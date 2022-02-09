#!/usr/bin/env zsh

export TERM='xterm-256color'

# Make vim the default editor.
export EDITOR='nvim'

# Enable persistent REPL history for `node`.
export NODE_REPL_HISTORY_FILE=~/.node_history

# Allow 32³ entries; the default is 1000.
export NODE_REPL_HISTORY_SIZE='32768'

# Increase Bash history size. Allow 32³ entries; the default is 500.
export HISTSIZE=1000000
export HISTFILESIZE="${HISTSIZE}"

# Add timestamps to Bash history entries.
export HISTTIMEFORMAT="%d/%m/%y %T"

# Omit duplicates and commands that begin with a space from history.
export HISTCONTROL='ignoreboth:erasedups'

# Ignore some useless commands in history
export HISTIGNORE='&:ls:[bf]g:exit:pwd:clear:mount:umount:history'

# Linker and compiler flags for zlib
export LDFLAGS="-L/usr/local/opt/zlib/lib"
export CPPFLAGS="-I/usr/local/opt/zlib/include"

# Prefer US English and use UTF-8.
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'
export LC_CTYPE='en_US.UTF-8'

# Don’t clear the screen after quitting a manual page.
export MANPAGER='less -X'

# Colorful MAN pages.
export PAGER=most

# Colorful less.
LESSPIPE=`which src-hilite-lesspipe.sh`
export LESSOPEN="| ${LESSPIPE} %s"
export LESS=' -R -X -F '

# Always enable colored `grep` output.
export GREP_OPTIONS='--color=auto'

# Node Version Manager path.
export NVM_DIR=$XDG_CONFIG_HOME/nvm

# Node path.
export NODE_PATH="/usr/local/lib/node"

# Node environment.
export NODE_ENV=development

# Ant options.
export ANT_OPTS=-Dbuild.sysclasspath=ignore

# Homebrew
export HOMEBREW_INSTALL_CLEANUP=1

# Pyenv virtualenv
export PYENV_VIRTUALENV_DISABLE_PROMPT=1

# Set default AWS region and session TTL
export AWS_REGION=us-east-1
export AWS_SESSION_TTL=12h
export AWS_ASSUME_ROLE_TTL=12h

export XML_CATALOG_FILES="/usr/local/etc/xml/catalog"

export MYVIMRC=$XDG_CONFIG_HOME/nvim/init.vim
export TMUX_PLUGIN_MANAGER_PATH=$XDG_CONFIG_HOME/tmux/plugins/

# Starship prompt config
export STARSHIP_CONFIG=$DOTFILES/starship/starship.toml

# Prioritize using GNU commands over BSD commands
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
