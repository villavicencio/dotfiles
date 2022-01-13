require("plugins.configs.lspconfig")

vim.diagnostic.config {
  virtual_text = {
    prefix = "",
    spacing = 1,
  },
  signs = true,
  underline = true,
  update_in_insert = false,
}
