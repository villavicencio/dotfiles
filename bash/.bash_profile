#!/usr/bin/env bash

# Ignore shellcheck errors for sourced files
# shellcheck source=/dev/null

# Load dotfiles
source "$HOME/.config/bash/.options"      # Shell options
source "$HOME/.config/bash/.vars"         # Variables
source "$HOME/.config/bash/.path"         # Extend $PATH
source "$HOME/.config/bash/.exports"      # Define environment variables
source "$HOME/.config/bash/.functions"    # Bash functions
source "$HOME/.config/bash/.aliases"      # Define shortcuts
source "$HOME/.config/bash/.bash_prompt"  # Customize prompt and color scheme

# Load local/sensitive config that should not be committed.
[[ -r $HOME/.config/bash/.bashrc.local ]] && source "$HOME/.config/bash/.bashrc.local"

# Load Ruby Version Manager
[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"

brew_prefix=$(brew --prefix)
nvm_prefix=$(printenv NVM_DIR)

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
python -V 2>&1

# Print PHP version
php -i | grep 'PHP Version' | head -1

# Load bash-completion scripts.
if [[ -f $(brew --prefix)/etc/bash_completion ]]; then
	. "${brew_prefix}/etc/bash_completion"
fi

# Load bash completion support for Git.
source "$HOME/.git-completion.bash"

# Load fzf config if it exists.
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# Add tab completion for SSH hostnames based on ~/.ssh/config, ignoring wildcards
[[ -e "$HOME/.ssh/config" ]] && complete -o "default" -o "nospace" -W \
 "$(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2- | tr ' ' '\n')" scp sftp ssh;

# Ignore case in bash completion
bind "set show-all-if-ambiguous on"
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

# Ensure synchronization between bash memory and history file
export PROMPT_COMMAND="history -a; history -n; ${PROMPT_COMMAND}"

# If this is interactive shell, then bind hstr to Ctrl-r (for Vi mode check doc)
if [[ $- =~ .*i.* ]]; then bind '"\C-r": "\C-a hstr -- \C-j"'; fi

# If this is interactive shell, then bind 'kill last command' to Ctrl-x k
if [[ $- =~ .*i.* ]]; then bind '"\C-xk": "\C-a hstr -k \C-j"'; fi
