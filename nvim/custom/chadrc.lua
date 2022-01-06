-- This is an example chadrc file , its supposed to be placed in /lua/custom dir
-- lua/custom/chadrc.lua

local M = {}

-- make sure you maintain the structure of `core/default_config.lua` here,
-- example of changing theme:

-- NOTE: To use this, make a copy with `cp example_chadrc.lua chadrc.lua`

--------------------------------------------------------------------

-- To use this file, copy the strucutre of `core/default_config.lua`,
-- examples of setting relative number & changing theme:

-- M.options = {
--    relativenumber = true,
-- }

 -- M.ui = {
 --   theme = "uwu"
 -- }

-- NvChad included plugin options & overrides

M.plugins = {
   status = {
      dashboard = true,
   },
   default_plugin_config_replace = {
      lspconfig = "custom.plugins.lspconfig",
   },
 }

return M
