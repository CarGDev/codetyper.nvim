-- Codetyper.nvim - AI-powered coding partner for Neovim
-- Plugin loader

local g = vim.g
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

-- Prevent loading twice
if g.loaded_codetyper then
  return
end
g.loaded_codetyper = true

-- Minimum Neovim version check
if fn.has("nvim-0.8.0") == 0 then
  api.nvim_err_writeln("Codetyper.nvim requires Neovim 0.8.0 or higher")
  return
end

--- Initialize codetyper plugin (lazy initialization)
---@return boolean success
local function init_coder()
  local ok, err = pcall(function()
    local codetyper = require("codetyper")
    if not codetyper.is_initialized() then
      codetyper.setup()
    end
  end)

  if not ok then
    vim.notify("[Codetyper] Failed to initialize: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Lazy-load the plugin on first command usage
api.nvim_create_user_command("Coder", function(opts)
  require("codetyper").setup()
  cmd("Coder " .. (opts.args or ""))
end, {
  nargs = "?",
  complete = function()
    return {
      "tree",
      "tree-view",
      "reset",
      "gitignore",
    }
  end,
  desc = "Codetyper.nvim commands",
})

-- Lazy-load aliases
api.nvim_create_user_command("CoderTree", function()
  require("codetyper").setup()
  cmd("CoderTree")
end, { desc = "Refresh tree.log" })

api.nvim_create_user_command("CoderTreeView", function()
  require("codetyper").setup()
  cmd("CoderTreeView")
end, { desc = "View tree.log" })
