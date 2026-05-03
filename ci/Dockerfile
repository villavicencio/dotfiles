# Minimal Ubuntu 24.04 image used by .github/workflows/install-matrix.yml
# (PR #1b) to validate the install pipeline cross-platform on every PR.
#
# Mirrors the VPS production target documented in
# docs/solutions/cross-machine/vps-dotfiles-target.md:
#   - ubuntu:24.04 base
#   - root user (the install runbook expects root; install-linux.conf.yaml
#     assumes root)
#   - only the bootstrap deps that helpers/install_packages.sh does NOT
#     install itself; downstream apt installs are the install pipeline's
#     own concern
#
# This image is published to ghcr.io/<owner>/dotfiles-ci-ubuntu by
# .github/workflows/publish-ci-image.yml on master pushes that touch
# this file. Consumers pin to the SHA digest, not the :24.04 tag.
#
# The repo's checkout is mounted into the container at workflow runtime
# (`actions/checkout@v4` + the runner's working-directory mount) — the
# image intentionally does NOT bake the dotfiles repo in, so image
# rebuilds aren't required when repo content changes.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        sudo \
        zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

CMD ["bash"]
