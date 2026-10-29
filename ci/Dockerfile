# Minimal Ubuntu 26.04 image used by the install-matrix workflow to
# validate the install pipeline cross-platform on every PR.
#
# Bare Ubuntu server, as root, with only the bootstrap deps install_packages.sh
# doesn't install itself. Published by publish-ci-image.yml; consumers pin the digest.
# The repo is mounted at runtime, not baked in. Why each choice:
# docs/reference/wsl-linux.md ("CI image").
# Bump the base digest with `docker buildx imagetools inspect ubuntu:26.04`.
FROM ubuntu:26.04@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

ENV DEBIAN_FRONTEND=noninteractive

# sudo: install_packages.sh calls `sudo apt-get` even as root. python3, not
# python3-minimal: Dotbot needs the stdlib. ForceIPv4 must come first in the chain so
# the build's own apt calls skip the runner's IPv6 timeouts (#65).
RUN printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99-force-ipv4 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        python3 \
        sudo \
        zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

CMD ["bash"]
