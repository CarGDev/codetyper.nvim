---@mod codetyper Codetyper.nvim - AI-powered coding partner
---@brief [[
--- Codetyper.nvim is a Neovim plugin that acts as your coding partner.
--- It uses LLM APIs (Claude, Ollama) to help you write code faster
--- using special `.coder.*` files and inline prompt tags.
---@brief ]]

local M = {}

---@type CoderConfig
M.config = {}

---@type boolean
M._initialized = false

--- Setup the plugin with user configuration
---@param opts? CoderConfig User configuration options
function M.setup(opts)
  if M._initialized then
    return
  end

  local config = require("codetyper.config")
  M.config = config.setup(opts)

  -- Initialize modules
  local commands = require("codetyper.commands")
  local gitignore = require("codetyper.gitignore")
  local autocmds = require("codetyper.autocmds")
  local tree = require("codetyper.tree")

  -- Register commands
  commands.setup()

  -- Setup autocommands
  autocmds.setup()

  -- Ensure .gitignore has coder files excluded
  gitignore.ensure_ignored()

  -- Initialize tree logging (creates .coder folder and initial tree.log)
  tree.setup()

  M._initialized = true

  -- Auto-open Ask panel after a short delay (to let UI settle)
  if M.config.auto_open_ask then
    vim.defer_fn(function()
      local ask = require("codetyper.ask")
      if not ask.is_open() then
        ask.open()
      end
    end, 300)
  end
end

--- Get current configuration
---@return CoderConfig
function M.get_config()
  return M.config
end

--- Check if plugin is initialized
---@return boolean
function M.is_initialized()
  return M._initialized
end

return M
