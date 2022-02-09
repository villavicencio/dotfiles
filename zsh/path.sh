#!/usr/bin/env sh

export PATH="/usr/local/bin:/usr/local/sbin:/home/linuxbrew/.linuxbrew/bin:$PATH"

# Add brew curl first to path
export PATH="/usr/local/opt/curl/bin:$PATH"

# Add MySQL to path
export PATH="$PATH:/usr/local/mysql/bin"

# Add RVM to PATH for scripting
export PATH="$PATH:$HOME/.rvm/bin"

# Add Yarn to PATH
export PATH="$PATH:$HOME/.yarn/bin"

# Add cargo-installed binaries to the path
export PATH="$PATH:$CARGO_HOME/bin"

# Add my experimental stuff to PATH
export PATH="$PATH:$HOME/bin";
export PATH="$PATH:$HOME/.local/bin";

# Export openssl compiler flags
export LDFLAGS="-L/usr/local/opt/openssl/lib"
export CPPFLAGS="-I/usr/local/opt/openssl/include"
