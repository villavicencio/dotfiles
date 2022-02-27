local wk = require("which-key")

wk.setup {
  ignore_missing = true,
  icons = {
    group = "",
  },
  layout = {
    spacing = 10,
  },
}

wk.register({
  f = {
    name = "  File",
    f = { "<cmd>Telescope find_files<cr>", "Find File" }, -- create a binding with label
    r = { "<cmd>Telescope oldfiles<cr>", "Open Recent File", noremap=false }, -- additional options for creating the keymap
    g = { "<cmd>Telescope live_grep<cr>", "Live Grep" },
  },
  z = {
    name = "  Zen Mode",
    f = { "<cmd>TZFocus<cr>", "Focus" },
    m = { "<cmd>TZMinimalist<cr>", "Minimalist" },
    z = { "<cmd>TZAtaraxis<cr>", "Ataraxis" },
  },
  t = { "<cmd>execute '90vnew +terminal' | let b:term_type = 'vert' | startinsert <cr>", "  Terminal" },
  w = {
    name = "  Vimwiki",
    w = { "<cmd>VimwikiIndex<cr>", "Open Index" },
    r = { "<cmd>VimwikiRenameFile<cr>", "Rename File" },
  },
  x = { require("core.utils").close_buffer(), "  Close Buffer" },
}, { prefix = "<leader>" })
