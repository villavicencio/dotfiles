#!/usr/bin/env bash
[ -n "$PS1" ] && source $HOME/.bash_profile;

export PATH="$HOME/.yarn/bin:$PATH"

# tabtab source for serverless package
# uninstall by removing these lines or running `tabtab uninstall serverless`
[ -f /Users/david/.nvm/versions/node/v10.11.0/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.bash ] && . /Users/david/.nvm/versions/node/v10.11.0/lib/node_modules/serverless/node_modules/tabtab/.completions/serverless.bash
# tabtab source for sls package
# uninstall by removing these lines or running `tabtab uninstall sls`
[ -f /Users/david/.nvm/versions/node/v10.11.0/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.bash ] && . /Users/david/.nvm/versions/node/v10.11.0/lib/node_modules/serverless/node_modules/tabtab/.completions/sls.bash
