-- Conceal links
vim.g['pandoc#syntax#conceal#urls'] = 1

require('autocmd-lua').augroup {
  group = 'markdown',
  autocmds = {
    {
      event = 'FileType',
      pattern = 'markdown,markdown.pandoc,vimwiki',
      cmd = function()
        vim.cmd([[
          " Bold headers in markdown
          highlight title gui=bold cterm=bold
          
          " Transparent background color on concealed text
          highlight Conceal ctermbg=NONE guibg=NONE
          
          " Set soft wrap when editing markdown
          call pencil#init({'wrap': 'soft'})
          
          " Enable markdown table helper
          call tablemode#Enable()
        ]])
      end
    },
  },
}
