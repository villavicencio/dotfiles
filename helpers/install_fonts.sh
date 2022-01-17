#!/bin/bash

if test $(uname 2> /dev/null) = "Darwin"
then
  cp fonts/* ~/Library/Fonts/
else
  cp fonts/* ~/.local/share/fonts/
fi
