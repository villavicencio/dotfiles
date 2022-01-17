#!/bin/bash

. helpers/env.sh

if test ! -d ~/.config/kymsu && test $(uname 2> /dev/null) = "Darwin"
then
  $(git clone "https://github.com/welcoMattic/kymsu" ~/.config/kymsu \
    && cd ~/.config/kymsu && ./install.sh)
fi
