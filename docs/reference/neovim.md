# Neovim plugin pins

Moved out of the always-loaded `CLAUDE.md` on 2026-10-22 (VIL-402), word for word except
for heading levels. `CLAUDE.md` keeps the one-line rules and points here.

## Neovim plugin pins — the first launch on an empty machine drifts them
`nvim/lazy-lock.json` is reached through the `~/.config/nvim` link, and lazy.nvim's first
install **rewrites it**. It installs in rounds; NvChad's own plugins are only known once
NvChad is on disk, and the lockfile write between rounds drops their entries, so those
plugins land at their branch HEAD and the drifted commits are written back. A later
`Lazy! restore` restores *to that rewritten file*, so it looks green. On 2026-09-24,
9 of 27 pins drifted this way.

`helpers/install_nvim.sh` and `windows/install_nvim.ps1` therefore keep a copy of the pins,
bootstrap, put the copy back, restore, and verify against the copy with
`helpers/nvim_verify_lock.lua`. **Don't collapse this back into a single `Lazy! restore`
pass.** Before any of that, both helpers resolve nvim's config dir (symlinks and junctions
followed) and exit 1 without touching it unless it is this repo's `nvim/`: Dotbot leaves an
existing real `~/.config/nvim` in place, and a real `%LOCALAPPDATA%\nvim` that can't be moved
aside blocks the Windows link. `install.ps1` also skips the helper, recording a failure, when
`%LOCALAPPDATA%\nvim` isn't its link. CI's post-apply R9 check fails if `./install` leaves the lockfile modified. The
minimum Neovim version is **0.12**, because the pinned nvim-treesitter (`main`) requires it.
An installed nvim below that is upgraded (`brew upgrade neovim` / `winget upgrade`), and
the helper fails if it is still too old. It never skips with exit 0, because the package
steps only install what is missing. A missing nvim is a failure too. The snapshot is
checked (non-empty, byte-equal) before nvim starts. A restore writes a sibling temp file,
checks it, and renames it over the lockfile, so the tracked file is never truncated. The
pins are restored again after the final load check. If the run fails, the snapshot is kept
and its path printed. On Linux, a reused `~/.local/opt/nvim-v<ver>` must carry the
sha256 marker the helper writes at install time; otherwise it is moved aside and reinstalled. Success also requires
both nvim passes to exit 0 and a clean headless load of the config (`nvconfig` loaded,
no output). `nvim --headless` exits 0 even when `init.lua` errors, so exit codes alone
prove nothing. On Linux, anything already at `~/.local/bin/nvim` (other than a symlink)
or at the version dir is moved to `<name>.pre-dotfiles`, never deleted.
Write-up: `docs/solutions/runtime-errors/lazy-nvim-first-launch-drifts-lockfile-2026-09-24.md`.
