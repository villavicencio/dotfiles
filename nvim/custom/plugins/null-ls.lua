local null_ls = require "null-ls"
local b = null_ls.builtins

local sources = {
  -- webdev stuff
  b.formatting.deno_fmt,
  b.formatting.prettierd.with {
    filetypes = {
      "html",
      "markdown",
      "css"
    }
  },

  -- Lua
  b.formatting.stylua,
  b.diagnostics.luacheck.with {
    extra_args = {
      "--global vim"
    }
  },

  -- Shell
  b.formatting.shfmt,
  b.diagnostics.shellcheck.with {
    diagnostics_format = "#{m} [#{c}]"
  },

  -- Vale
  b.diagnostics.vale.with ({
    filetypes = {
      "markdown",
      "tex",
      "markdown.pandoc"
    },
    extra_args = {
      "--config",
      vim.fn.expand("$DOTFILES/vale/vale.ini")
    }
  })
}

local M = {}

M.setup = function()
  null_ls.setup {
    debug = true,
    sources = sources,
    on_attach = function(client)
      if client.resolved_capabilities.document_formatting then
        vim.cmd("autocmd BufWritePre <buffer> lua vim.lsp.buf.formatting_sync()")
        vim.cmd[[ au FileType markdown.pandoc lua require("cmp").setup.buffer({completion={autocomplete=false}}) ]]
      end
    end,
  }
end

return M
