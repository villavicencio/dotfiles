return {
  {
    "Pocco81/TrueZen.nvim",

    cmd = {
      "TZAtaraxis",
      "TZMinimalist",
      "TZFocus",
    },

    config = function()
      require "nvim.custom.plugins.truezen"
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

  {
    "luukvbaal/stabilize.nvim",

    config = function()
      require("stabilize").setup()
    end,
  },

  {
    "SidOfc/mkdx",

    setup = function()
      require "custom.plugins.mkdx"
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
      require("custom.plugins.null-ls").setup()
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

  { "dhruvasagar/vim-table-mode" }
}
