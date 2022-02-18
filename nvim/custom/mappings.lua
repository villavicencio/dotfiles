local map = require("core.utils").map

map("n", "<leader>fg", ":Telescope live_grep <CR>", opt)
map("n", "<leader>q", ":q <CR>", opt)
map("n", "<leader>f", ":TZAtaraxis <CR>", opt)

-- Give me my tab back! 
vim.cmd'map <leader>j <Plug>VimwikiNextLink'
vim.cmd'map <leader>k <Plug>VimwikiPrevLink'
