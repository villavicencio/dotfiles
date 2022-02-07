local util = require 'lspconfig/util'

local M = {}

M.setup_lsp = function(attach, capabilities)
  local lspconfig = require "lspconfig"
  local runtime_path = vim.split(package.path, ';')
  
  table.insert(runtime_path, "lua/?.lua")
  table.insert(runtime_path, "lua/?/init.lua")

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
  
  require'lspconfig'.sumneko_lua.setup(require("nvim.custom.config.lua-lsp"))

  lspconfig.vimls.setup {
    cmd = { "vim-language-server", "--stdio" },
    filetypes = { "vim" },
    init_options = {
      diagnostic = {
        enable = true,
      },
      indexes = {
        count = 3,
        gap = 100,
        projectRootPatterns = { "runtime", "nvim", ".git", "autoload", "plugin" },
        runtimepath = true
      },
      iskeyword = "@,48-57,_,192-255,-#",
      runtimepath = "",
      suggest = {
        fromRuntimepath = true,
        fromVimruntime = true
      },
      vimruntime = ""
    },
    root_dir = function(fname)
      return util.find_git_ancestor(fname) or vim.fn.getcwd()
    end,
  }

  lspconfig.bashls.setup {
    cmd = { "bash-language-server", "start" },
    cmd_env = {
      GLOB_PATTERN = "*@(.sh|.inc|.bash|.command)"
    },
    filetypes = { "sh" },
    root_dir = util.find_git_ancestor,
    single_file_support = true
  }
end

return M
