local M = {}

local userPlugins = require "custom.plugins"

M.plugins = {
  status = {
    dashboard = true,
  },

  options = {
    lspconfig = {
      setup_lspconf = "custom.plugins.lspconfig_options",
    },
  },

  default_plugin_config_replace = {
    lspconfig = "custom.plugins.lspconfig",
    dashboard = "custom.plugins.dashboard",
  },

  install = userPlugins,
}

M.ui = {
  transparency = false,
}

return M
