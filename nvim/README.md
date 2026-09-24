# nvim

Neovim config — an **NvChad v2.5** starter, tracked here as the single source of truth and
linked as a whole directory to `~/.config/nvim` by Dotbot (see `dotbot-conf/base.yaml`), and to
`%LOCALAPPDATA%\nvim` on Windows by `install.ps1`.

- **Framework:** `NvChad/NvChad` (branch `v2.5`) is consumed as a *plugin* via `lazy.nvim`
  (`init.lua`), so this is a thin config over NvChad, not a fork of it.
- **Requires Neovim 0.12+** — the pinned `nvim-treesitter` (`main` branch) declares a 0.12
  minimum, `lua/configs/lspconfig.lua` uses `vim.lsp.enable` (0.11+), and `init.lua` uses
  `vim.uv`. Where it comes from:
  - **macOS:** Homebrew (`brew/Brewfile`).
  - **Linux / WSL:** `helpers/install_nvim.sh` installs the pinned official release tarball
    (sha256-checked) into `~/.local/opt/nvim-v<ver>` and links `~/.local/bin/nvim`, without
    sudo. Apt's `neovim` (0.9.5) is too old, so it is not in the apt list.
  - **Windows:** winget `Neovim.Neovim` (`windows/packages.json`).
- **Reproducible:** the plugin set is pinned in `lazy-lock.json`. `helpers/install_nvim.sh`
  (and `windows/install_nvim.ps1`, its Windows twin) bootstraps it headlessly without
  cloning NvChad or Packer, restores every plugin to its pin, and runs
  `helpers/nvim_verify_lock.lua` to fail closed if any plugin is off-pin. **The first launch
  on an empty machine drifts pins and rewrites the lockfile**, so the helpers keep a copy of
  the pins and put it back
  (`docs/solutions/runtime-errors/lazy-nvim-first-launch-drifts-lockfile-2026-09-24.md`).
  `:Lazy update` from inside nvim rewrites the committed lockfile through the symlink.
- **Customizations** (everything else is NvChad defaults): `lua/chadrc.lua` sets the `onedark`
  theme; `lua/mappings.lua` adds `;`→`:` and `jk`→`<ESC>`; `lua/configs/conform.lua` runs
  `stylua` on Lua; `lua/configs/lspconfig.lua` enables the `html` + `cssls` language servers
  on top of NvChad's `lua_ls`.
- **External tools the config uses:** `git`, `curl`, `tar`, and `ripgrep` (Telescope
  live-grep) are installed on every platform. `lua-language-server` comes from the Brewfile
  on macOS and from winget on Windows; on Linux, use `:MasonInstall lua-language-server`.
  `stylua` comes from `:MasonInstall stylua` everywhere. `html`/`cssls`
  (`:MasonInstall html-lsp css-lsp`) need Node/npm, which Windows does not have yet.
  Treesitter parsers beyond the ones bundled with Neovim (NvChad adds `luadoc` and `printf`)
  need the `tree-sitter` CLI (≥ 0.26.1) and a C compiler. No platform installs those; this
  is optional.

Layout: `init.lua` (lazy bootstrap + NvChad import), `lua/options.lua`, `lua/mappings.lua`,
`lua/chadrc.lua`, `lua/plugins/init.lua` (extra plugin specs), `lua/configs/` (per-plugin setup).

**Tracked-config caveat:** because `~/.config/nvim` is a symlink into this repo, two things
write back into tracked files at runtime — expected churn, not a bug: `:Lazy update` rewrites
`lazy-lock.json` (desirable — that's the pin), and NvChad's theme picker (`<leader>th`) rewrites
`lua/chadrc.lua` in place. Commit the lockfile bumps you want; for the theme file, either commit
the flip or `git update-index --skip-worktree nvim/lua/chadrc.lua` to ignore local theme changes.

Credit: [NvChad](https://github.com/NvChad/NvChad); the starter derives from the
[LazyVim starter](https://github.com/LazyVim/starter).
