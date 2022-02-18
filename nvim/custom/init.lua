require "custom.mappings"

-- Stop sourcing filetype.vim
vim.g.did_load_filetypes = 1

-- Set md filetype to pandoc
vim.cmd[[ au! BufNewFile,BufFilePre,BufRead *.md,*.jrnl set filetype=markdown.pandoc ]]
