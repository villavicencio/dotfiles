require "custom.mappings"

-- Stop sourcing filetype.vim
vim.g.did_load_filetypes = 1

-- Set md filetype to pandoc
vim.cmd[[ au! BufNewFile,BufFilePre,BufRead *.md set filetype=markdown.pandoc ]]

-- Set soft wrap when editing markdown
vim.cmd[[ autocmd FileType markdown,md,markdown.pandoc call pencil#init({'wrap': 'soft'}) ]]
