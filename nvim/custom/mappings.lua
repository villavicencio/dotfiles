local map = nvchad.map

-- Exit from terminal mode with escape key.
map("t", "<Esc>", "<C-\\><C-n>")

-- Give me my tab back!
map("n", "<leader>j", "<Plug>VimwikiNextLink")
map("n", "<leader>k", "<Plug>VimwikiPrevLink")
