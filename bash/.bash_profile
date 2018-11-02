#!/usr/bin/env bash

# Load the shell dotfiles
source $HOME/.path          # Extend $PATH
source $HOME/.bash_prompt   # Customize prompt and color scheme
source $HOME/.exports       # Define environment variables
source $HOME/.aliases       # Define shortcuts
source $HOME/.functions     # Bash functions

# Set system JDK.
#setJDK 1.8
#echo "Now using java v"$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')""

# Load NVM.
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Load RVM into shell session as a function.
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"

# Set system Node.js
nvm use v10.11.0

# Enable grunt shell tab auto-completion
eval "$(grunt --completion=bash)"

# Make Grunt print stack traces by default
command -v grunt > /dev/null && alias grunt="grunt --stack"

# Case-insensitive globbing (used in pathname expansion)
shopt -s nocaseglob;

# Append to the Bash history file, rather than overwriting it
shopt -s histappend;

# Autocorrect typos in path names when using `cd`
shopt -s cdspell;

# After each command, checks the windows size and changes lines and columns
shopt -s checkwinsize

# Enable some Bash 4 features when possible:
# * `autocd`, e.g. `**/qux` will enter `./foo/bar/baz/qux`
# * Recursive globbing, e.g. `echo **/*.txt`
for option in autocd globstar; do
	shopt -s "$option" 2> /dev/null;
done;

# Load bash-completion scripts.
if [ -f $(brew --prefix)/etc/bash_completion ]; then
	. $(brew --prefix)/etc/bash_completion
fi

# Load bash completion support for Git.
source $HOME/.git-completion.bash

# Load bash completion for Arcanist.
if [ -d "/usr/local/php/arcanist" ]; then
	export PATH="$PATH:/usr/local/php/arcanist/bin"
	source /usr/local/php/arcanist/resources/shell/bash-completion
fi

# Add tab completion for SSH hostnames based on ~/.ssh/config, ignoring wildcards
[ -e "$HOME/.ssh/config" ] && complete -o "default" -o "nospace" -W \
 "$(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2- | tr ' ' '\n')" scp sftp ssh;

# Ignore case in bash completion
bind "set completion-ignore-case on"

# No bell
bind "set bell-style none"

# Automatically show completion without double tab-ing.
bind "set show-all-if-ambiguous On"

# Add tab completion for `defaults read|write NSGlobalDomain`
# You could just use `-g` instead, but I like being explicit
complete -W "NSGlobalDomain" defaults;

# Add `killall` tab completion for common apps
complete -o "nospace" -W "Contacts Calendar Dock Finder Mail Safari iTunes SystemUIServer Terminal Twitter" killall;

# OPAM configuration
. /Users/david/.opam/opam-init/init.sh > /dev/null 2 > /dev/null || true

eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
echo "$(python -V 2>&1)"
php -i | grep 'PHP Version' | head -1

HISTIGNORE='suz'
