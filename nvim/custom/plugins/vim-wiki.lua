-- Add Pandoc markdown to vimwiki.
vim.g['pandoc#filetypes#handled'] = {"pandoc", "markdown"}
vim.cmd[[ au FileType vimwiki set syntax=markdown.pandoc ]]
vim.g.vimwiki_global_ext = 0

-- Register wiki with options.
vim.g.vimwiki_list = {
  {
    path = '~/Library/Mobile Documents/iCloud~md~obsidian/Documents/My Second Brain/wiki/',
    syntax = 'markdown',
    ext = '.md',
    name = 'My Second Brain',
    auto_toc = 1,
    index = '+ Scratchpad'
  }
}
