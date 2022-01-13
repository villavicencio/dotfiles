local util = require 'lspconfig/util'

local M = {}

M.setup_lsp = function(attach, capabilities)
  local lspconfig = require "lspconfig"
  local runtime_path = vim.split(package.path, ';')
  
  table.insert(runtime_path, "lua/?.lua")
  table.insert(runtime_path, "lua/?/init.lua")

  local servers = { "sumneko_lua", "vimls" }

  for _, lsp in ipairs(servers) do
    lspconfig[lsp].setup {
      on_attach = attach,
      capabilities = capabilities,
      flags = {
        debounce_text_changes = 150,
      },
    }
  end

  lspconfig.sumneko_lua.setup {
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = 'LuaJIT',
          -- Setup your lua path
          path = runtime_path,
        },
        diagnostics = {
          -- Get the language server to recognize the `vim` global
          globals = {'vim'},
        },
        workspace = {
          -- Make the server aware of Neovim runtime files
          library = vim.api.nvim_get_runtime_file("", true),
        },
        -- Do not send telemetry data containing a randomized but unique identifier
        telemetry = {
          enable = false,
        },
      },
    },
  }

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
end

return M
