local g = vim.g

g.dashboard_disable_at_vimenter = 0
g.dashboard_disable_statusline = 1
g.dashboard_preview_command = "cat"
g.dashboard_preview_pipeline = "lolcat"
g.dashboard_preview_file = vim.fn.expand("$DOTFILES/nvim/custom/logo")
g.dashboard_preview_file_height = 10
g.dashboard_preview_file_width = 62
g.dashboard_default_executive = "telescope"
g.dashboard_custom_section = {
   a = { description = { "  Find File                 SPC f f" }, command = "Telescope find_files" },
   b = { description = { "  Recents                   SPC f o" }, command = "Telescope oldfiles" },
   c = { description = { "  Find Word                 SPC f w" }, command = "Telescope live_grep" },
   d = { description = { "洛 New File                  SPC f n" }, command = "DashboardNewFile" },
   e = { description = { "  Bookmarks                 SPC b m" }, command = "Telescope marks" },
   f = { description = { "  Load Last Session         SPC l  " }, command = "SessionLoad" },
}
-- g.dashboard_custom_header = {}
-- g.dashboard_header = {}
-- g.dashboard_custom_footer = {
--    "   ",
-- }

