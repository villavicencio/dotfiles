local M = {}

local userPlugins = require "custom.plugins"

M.plugins = {
  status = {
    alpha = true,
  },

  options = {
    lspconfig = {
      setup_lspconf = "custom.plugins.lspconfig_options",
    },
  },

  default_plugin_config_replace = {
    lspconfig = "custom.plugins.lspconfig",
    -- alpha = "custom.plugins.dashboard",
  },

  install = userPlugins,
}

M.ui = {
  transparency = false,
}

return M
