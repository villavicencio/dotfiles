---
title: "lazy.nvim's first launch drifts the pins and rewrites lazy-lock.json, so a later `Lazy! restore` looks green"
date: 2026-09-24
category: runtime-errors
tags:
  - nvim
  - lazy.nvim
  - nvchad
  - lockfile
  - reproducibility
  - windows
  - wsl
severity: Medium
component: "helpers/install_nvim.sh, windows/install_nvim.ps1, helpers/nvim_verify_lock.lua"
problem_type: "silent pin drift in a headless plugin bootstrap"
module: "nvim"
related_solutions:
  - "docs/solutions/cross-machine/wsl-ubuntu-target-2026-09-24.md: the WSL target whose nvim gap (VIL-152) surfaced this"
  - "docs/solutions/best-practices/verify-the-instrument-before-trusting-a-negative.md: the same shape, a check that reads what the bug wrote"
---

# lazy.nvim's first launch drifts the pins and rewrites lazy-lock.json

## Symptom

On a machine with no plugins yet, the first `nvim` start (headless or not) installs
the plugin set and leaves `nvim/lazy-lock.json` **modified in the repo** — the file is
reached through the `~/.config/nvim` (or `%LOCALAPPDATA%\nvim`) directory link. On
2026-09-24, a fresh Windows bootstrap with Neovim 0.12.5 changed 9 of the 27 pins:
`base46`, `friendly-snippets`, `gitsigns.nvim`, `indent-blankline.nvim`, `lazy.nvim`,
`nvim-tree.lua`, `nvim-treesitter`, `nvim-web-devicons`, `ui`. Each was checked out at
its branch HEAD, not its pin.

The old `install_nvim.sh` could not notice this. Its first pass was
`nvim --headless "+Lazy! restore" +qa`, and the startup install runs *before* the
`+Lazy! restore` command, so the restore read the lockfile the install had just
rewritten. It then "restored" to the drifted commits, and the verify step compared
the plugins against that same rewritten file. Everything passed, and the only visible
sign was a dirty `nvim/lazy-lock.json`.

## Cause

lazy.nvim installs missing plugins **in rounds** (`lazy.core.loader.install_missing`).
Plugins that come from `import = "nvchad.plugins"` are unknown until NvChad itself is
on disk, so round one installs NvChad and the config's own specs, then calls
`lazy.manage.lock.update()`. That function **drops every lock entry for a plugin it
does not currently know** (only disabled or `cond` plugins are kept), then writes the
file. Round two installs NvChad's plugins with `lockfile = true`, but their entries
are already gone from the in-memory lock, so they get checked out at HEAD and written
back as the new pins.

The bootstrap clone in `init.lua` (`--branch=stable`) causes the `lazy.nvim` entry to
drift as well.

Every platform does this: it follows from any config that imports its plugin specs
from a plugin. Windows was just where it was first seen, because the bootstrap was
being tested against a throwaway data dir.

## Fix

Keep the committed pins outside the file lazy.nvim rewrites, and put them back:

1. copy `lazy-lock.json` to a temp file (the pins);
2. `nvim --headless +qa`: bootstrap and install, which may drift;
3. copy the pins back, then `nvim --headless "+Lazy! restore" +qa`;
4. copy the pins back again, then verify **against the copy**, not the live file.

Both `helpers/install_nvim.sh` and `windows/install_nvim.ps1` follow this sequence and
share one verifier, `helpers/nvim_verify_lock.lua`. It runs under `nvim -l`, so it
needs no `python3`; on Windows, `python3` is often the Microsoft Store stub. The CI
post-apply action (R9) also runs `git diff --exit-code -- nvim/lazy-lock.json` after
`./install`, so a return of the drift fails the build.

## Also found while testing on Windows

- **The pinned nvim-treesitter (`main`) requires Neovim 0.12**, according to its own
  `health.lua`. The documented minimum was 0.11, so it was raised to 0.12.
- **Parser installs need `tree-sitter` CLI ≥ 0.26.1 plus a C compiler.** Neither is in
  the Brewfile or `windows/packages.json`, and neither Mac nor Windows has them by
  default. Neovim 0.12 bundles the `c`, `lua`, `markdown`, `query`, `vim`, and
  `vimdoc` parsers, so Lua and Vim files highlight without them. Only NvChad's extra
  `luadoc` and `printf` parsers are missing.
- **Keep throwaway test dirs short.** `vim.loader` writes its byte-code cache as one
  file named after the full source path, URL-encoded. Under a deep temp dir that
  name went past the 255-character NTFS limit, and startup failed with `ENOENT` on a
  `…icons_by_filename.luac` path. Enabling `LongPathsEnabled` does not help, because
  it lifts the total path limit, not the per-name limit. Real `%LOCALAPPDATA%` paths
  are well under it.
