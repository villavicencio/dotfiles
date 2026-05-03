# Minimal Ubuntu 24.04 image used by the install-matrix workflow to
# validate the install pipeline cross-platform on every PR.
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
#
# Base image is SHA-pinned (manifest-list digest, multi-arch) to close
# the upstream supply-chain gap symmetrically with the consumer-side
# digest pin. Update via `docker buildx imagetools inspect ubuntu:24.04`
# when Canonical ships base-image patches.
FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

ENV DEBIAN_FRONTEND=noninteractive

# Container runs as root (no USER directive). sudo is intentionally not
# installed — it would be dead code at root and adds CVE surface.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

CMD ["bash"]
