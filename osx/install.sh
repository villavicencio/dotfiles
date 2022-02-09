#!/usr/bin/env sh

# Manual installs
# Caffeine: http://lightheadsw.com/caffeine/
# Spotify: https://www.spotify.com/us/download/mac

if [ "$(uname)" != "Darwin" ]; then
    exit
fi

if ! which brew &> /dev/null; then
    echo "Installing homebrew"
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Brew packages
echo "Installing Brew packages"
brew tap "homebrew/bundle"
brew tap "homebrew/cask"
brew tap "homebrew/cask-fonts"
brew tap "homebrew/core"
brew tap "homebrew/services"
brew tap "saulpw/vd"
brew install \
        "ack" `# Search tool like grep, but optimized for programmers` \
        "openssl@1.1" `# Cryptography and SSL/TLS Toolkit` \


