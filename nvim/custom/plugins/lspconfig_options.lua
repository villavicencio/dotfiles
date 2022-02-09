local M = {}

M.setup_lsp = function(attach, capabilities)
  local lspconfig = require "lspconfig"

  local servers = { "sumneko_lua", "vimls", "bashls" }

  for _, lsp in ipairs(servers) do
    lspconfig[lsp].setup {
      on_attach = attach,
      capabilities = capabilities,
      flags = {
        debounce_text_changes = 150,
      },
    }
  end

  lspconfig.sumneko_lua.setup(require("nvim.custom.config.lua-lsp"))

  lspconfig.vimls.setup(require("nvim.custom.config.vim-lsp"))

  lspconfig.bashls.setup(require("nvim.custom.config.bash-lsp"))
end

return M
