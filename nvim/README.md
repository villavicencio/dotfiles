# nvim

Neovim config — an **NvChad v2.5** starter, tracked here as the single source of truth and
symlinked to `~/.config/nvim` by Dotbot (whole-directory link; see `dotbot-conf/base.yaml`).

- **Framework:** `NvChad/NvChad` (branch `v2.5`) is consumed as a *plugin* via `lazy.nvim`
  (`init.lua`), so this is a thin config over NvChad, not a fork of it.
- **Requires Neovim 0.11+** — `init.lua` uses `vim.uv`, `lua/configs/lspconfig.lua` uses
  `vim.lsp.enable`, and the pinned NvChad declares a 0.11 minimum. macOS gets a current nvim
  from Homebrew; on Ubuntu the apt package (0.9.5) is too old — use the unstable PPA, snap, or
  an AppImage. `install_nvim.sh` version-guards and skips the bootstrap on older nvim.
- **Reproducible:** the plugin set is pinned in `lazy-lock.json`. `helpers/install_nvim.sh`
  bootstraps it headlessly with `nvim --headless "+Lazy! restore" +qa` — no NvChad/Packer clone —
  then verifies every plugin is checked out at its locked commit (fails closed otherwise).
  `:Lazy update` from inside nvim rewrites the committed lockfile through the symlink.
- **Customizations** (everything else is NvChad defaults): `lua/chadrc.lua` sets the `onedark`
  theme; `lua/mappings.lua` adds `;`→`:` and `jk`→`<ESC>`; `lua/configs/conform.lua` runs
  `stylua` on Lua; `lua/configs/lspconfig.lua` enables the `html` + `cssls` language servers
  (install their servers via `:Mason`).

Layout: `init.lua` (lazy bootstrap + NvChad import), `lua/options.lua`, `lua/mappings.lua`,
`lua/chadrc.lua`, `lua/plugins/init.lua` (extra plugin specs), `lua/configs/` (per-plugin setup).

**Tracked-config caveat:** because `~/.config/nvim` is a symlink into this repo, two things
write back into tracked files at runtime — expected churn, not a bug: `:Lazy update` rewrites
`lazy-lock.json` (desirable — that's the pin), and NvChad's theme picker (`<leader>th`) rewrites
`lua/chadrc.lua` in place. Commit the lockfile bumps you want; for the theme file, either commit
the flip or `git update-index --skip-worktree nvim/lua/chadrc.lua` to ignore local theme changes.

Credit: [NvChad](https://github.com/NvChad/NvChad); the starter derives from the
[LazyVim starter](https://github.com/LazyVim/starter).
