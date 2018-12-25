#!/usr/bin/env bash

# Load dotfiles
source $HOME/.config/bash/.options      # Shell options
source $HOME/.config/bash/.path         # Extend $PATH
source $HOME/.config/bash/.exports      # Define environment variables
source $HOME/.config/bash/.bash_prompt  # Customize prompt and color scheme
source $HOME/.config/bash/.functions    # Bash functions
source $HOME/.config/bash/.aliases      # Define shortcuts

# Load Ruby Version Manager
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"

brew_prefix=$(brew --prefix)
nvm_prefix=$(printenv NVM_DIR)
cls_prefix=$(dirname $(gem which colorls))

# Set system JDK
#jdk_set 1.8
#echo "Now using java v"$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')""

# Load Node Version Manager
[[ -s "${nvm_prefix}/nvm.sh" ]] && . "${nvm_prefix}/nvm.sh"

# Print Node version
echo "Node $(node -v 2>&1) (npm $(npm -v 2>&1))"

# Set and print Python version
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
echo "$(python -V 2>&1)"

# Print PHP version
php -i | grep 'PHP Version' | head -1

# Enable grunt shell tab auto-completion
eval "$(grunt --completion=bash)"

# Make Grunt print stack traces by default
command -v grunt > /dev/null && alias grunt="grunt --stack"

# Load bash-completion scripts.
if [[ -f $(brew --prefix)/etc/bash_completion ]]; then
	. ${brew_prefix}/etc/bash_completion
fi

# Load bash completion support for Git.
source $HOME/.git-completion.bash

# Load bash completion for colorls gem.
source ${cls_prefix}/tab_complete.sh

# Load bash completion for Arcanist.
if [[ -d "/usr/local/php/arcanist" ]]; then
	export PATH="$PATH:/usr/local/php/arcanist/bin"
	source /usr/local/php/arcanist/resources/shell/bash-completion
fi

# Add tab completion for SSH hostnames based on ~/.ssh/config, ignoring wildcards
[[ -e "$HOME/.ssh/config" ]] && complete -o "default" -o "nospace" -W \
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

# Ignore some useless commands in history
HISTIGNORE='&:ls:[bf]g:exit:pwd:clear:mount:umount:suz:history'
