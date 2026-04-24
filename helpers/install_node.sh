#!/bin/bash

. ./zsh/zshenv
. $NVM_DIR/nvm.sh

current_version=$(nvm current)

if [ "${DOTFILES_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run] would nvm install $NODE_VERSION + refresh ~/.local/bin symlinks"
  exit 0
fi

nvm install $NODE_VERSION
nvm alias default $NODE_VERSION
nvm reinstall-packages $current_version
nvm install-latest-npm

sed 's/#.*//' npm/npm-requirements.txt | xargs npm install -g

# Refresh ~/.local/bin/{node,npm,npx} symlinks pointing at the managed NVM
# version. Non-zsh subshells (Claude Code plugin hooks, Starship custom modules,
# any tool shelling out via /bin/sh or bash) never run zshrc and therefore miss
# NVM's lazy loader — they fall back to whatever bare `node` resolves to on the
# base PATH. Seeding ~/.local/bin (ahead of /usr/local/bin via zshenv's
# LOCAL_SHARE_BIN) with the correct binaries is the defensive mitigation.
# Pinned to NODE_VERSION so every install_node.sh run refreshes these to match.
NODE_BIN="$NVM_DIR/versions/node/v$NODE_VERSION/bin"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
for bin in node npm npx; do
  ln -sf "$NODE_BIN/$bin" "$LOCAL_BIN/$bin"
done
