#!/bin/bash

. ./zsh/zshenv
. $NVM_DIR/nvm.sh

current_version=$(nvm current)

nvm install $NODE_VERSION
nvm alias default $NODE_VERSION
nvm reinstall-packages $current_version
nvm install-latest-npm

sed 's/#.*//' npm/npm-requirements.txt | xargs npm install -g
