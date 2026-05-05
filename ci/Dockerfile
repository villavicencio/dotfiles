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

# Container runs as root (no USER directive). sudo is still required even
# at root because helpers/install_packages.sh on Linux invokes
# `sudo apt-get install ...` — at root sudo acts as a no-op trampoline
# but the binary must resolve on PATH or the helper aborts and downstream
# helpers (install_tmux.sh etc.) cascade-fail with "tmux: command not
# found". An earlier image revision left sudo out and install-matrix.yml
# had to apt-install it at runtime as a workflow bootstrap step (see
# issue #58); baking it in here removes that round-trip.
#
# python3 (not python3-minimal): Dotbot is a Python script
# (dotbot/bin/dotbot exec's python3 "$0") and does `import json` /
# `import yaml` at startup. python3-minimal strips the stdlib, so
# `import json` raises ModuleNotFoundError. The full python3
# metapackage pulls libpython3-stdlib (~45MB) and matches what
# Ubuntu Server (the VPS production target) ships out of the box.
#
# Acquire::ForceIPv4: archive.ubuntu.com resolves to Cloudflare CDN
# IPv6 (2606:4700:10::*). When the GH Actions Azure-eastus runner
# network can't reach those endpoints, every fresh apt connection
# waits ~60s for the IPv6 SYN to time out before falling back to IPv4
# — that's the classic 60-69s gap signature observed on 2026-05-04
# (#65). Forcing IPv4 at the image level skips the IPv6 attempt
# entirely. Image-level (not workflow runtime, not install-pipeline
# runtime) because (a) earlier apt invocations would miss runtime
# injection, (b) the install pipeline also runs on the VPS where
# IPv4 forcing is wasted opinion. See
# docs/solutions/cross-machine/install-matrix-ipv6-fallback-misattribution-2026-05-05.md
# for the full investigation.
#
# The printf MUST be the first link in the chain so the image build's
# own apt-get update / apt-get install also benefit. Writing it after
# the apt calls would protect runtime consumers but leave publish-ci-image.yml
# itself exposed to the same IPv6 fallback this is meant to prevent.
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
