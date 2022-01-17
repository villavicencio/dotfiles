#!/bin/bash

. helpers/env.sh

if ! command -v brew
then
    /bin/bash -c "$(curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")" </dev/null
fi
