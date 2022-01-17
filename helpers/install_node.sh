#!/bin/bash

. helpers/env.sh

current_version=`nvm current`

if test $current_version != "$NODE_VERSION"
then
  nvm install $NODE_VERSION
  nvm alias default $NODE_VERSION

  if test $current_version != "none"
  then
    nvm reinstall-packages $current_version 
  fi
fi

nvm install-latest-npm
sed 's/#.*//' npm/npm-requirements.txt | xargs npm install -g
