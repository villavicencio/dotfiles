return {
  {
    "Pocco81/TrueZen.nvim",
    
    cmd = {
      "TZAtaraxis",
      "TZMinimalist",
      "TZFocus",
    },
    
    config = function()
      -- check https://github.com/Pocco81/TrueZen.nvim#setup-configuration (init.lua version)
    end,
  },
  
  {
    "karb94/neoscroll.nvim",
    
    opt = true,
    
    config = function()
      require("neoscroll").setup()
    end,
    
    -- lazy loading
    setup = function()
      require("core.utils").packer_lazy_load "neoscroll.nvim"
    end,
  },

  { "nathom/filetype.nvim" },

  {
    "luukvbaal/stabilize.nvim",
    
    config = function()
      require("stabilize").setup()
    end,
  },

  {
    "SidOfc/mkdx",

    setup = function()
      -- Disable tab mapping which was preventing tabbing buffers
      vim.g["mkdx#settings"] = {
        tab = { enable = 0 },
      }
    end,
  },

  {
    "vim-pandoc/vim-pandoc-syntax",

    setup = function ()
      -- Conceal links
      vim.g["pandoc#syntax#conceal#urls"] = 1
    end,
  },

  { "reedes/vim-pencil" },

  {
    "jose-elias-alvarez/null-ls.nvim",
    
    after = "nvim-lspconfig",
    
    config = function()
      require("null-ls").setup({
        sources = {
          require("null-ls").builtins.diagnostics.vale.with({
            filetypes = { "markdown", "tex", "markdown.pandoc" },
            extra_args = {
              "--config",
              vim.fn.expand("$DOTFILES/vale/vale.ini"),
            },
          }),
        },
        on_attach = function(client)
          if client.resolved_capabilities.document_formatting then
            vim.cmd("autocmd BufWritePre <buffer> lua vim.lsp.buf.formatting_sync()")
            vim.cmd[[ au FileType markdown.pandoc lua require("cmp").setup.buffer({completion={autocomplete=false}}) ]]
          end
        end,
      })
    end,
    
    requires = { "nvim-lua/plenary.nvim" },
  },

  {
    "folke/which-key.nvim",
    
    config = function()
      require("which-key").setup {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    end,
  },

  {
    "gbprod/cutlass.nvim",
    
    config = function()
      require("cutlass").setup({
        cut_key = "x"
      })
    end,
  },
}
