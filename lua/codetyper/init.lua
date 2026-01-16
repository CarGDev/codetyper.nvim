---@mod codetyper Codetyper.nvim - AI-powered coding partner
---@brief [[
--- Codetyper.nvim is a Neovim plugin that acts as your coding partner.
--- It uses LLM APIs (OpenAI, Gemini, Copilot, Ollama) to help you
--- write code faster using special `.coder.*` files and inline prompt tags.
--- Features an event-driven scheduler with confidence scoring and
--- completion-aware injection timing.
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

  local config = require("codetyper.config.defaults")
  M.config = config.setup(opts)

  -- Initialize modules
  local commands = require("codetyper.adapters.nvim.commands")
  local gitignore = require("codetyper.support.gitignore")
  local autocmds = require("codetyper.adapters.nvim.autocmds")
  local tree = require("codetyper.support.tree")
  local completion = require("codetyper.features.completion.inline")
  local logs_panel = require("codetyper.adapters.nvim.ui.logs_panel")

  -- Register commands
  commands.setup()

  -- Setup autocommands
  autocmds.setup()

  -- Setup file reference completion
  completion.setup()

  -- Setup logs panel (handles VimLeavePre cleanup)
  logs_panel.setup()

  -- Ensure .gitignore has coder files excluded
  gitignore.ensure_ignored()

  -- Initialize tree logging (creates .coder folder and initial tree.log)
  tree.setup()

  -- Initialize project indexer if enabled
  if M.config.indexer and M.config.indexer.enabled then
    local indexer = require("codetyper.features.indexer")
    indexer.setup(M.config.indexer)
  end

  -- Initialize brain learning system if enabled
  if M.config.brain and M.config.brain.enabled then
    local brain = require("codetyper.core.memory")
    brain.setup(M.config.brain)
  end

  -- Setup inline ghost text suggestions (Copilot-style)
  if M.config.suggestion and M.config.suggestion.enabled then
    local suggestion = require("codetyper.features.completion.suggestion")
    suggestion.setup(M.config.suggestion)
  end

  -- Start the event-driven scheduler if enabled
  if M.config.scheduler and M.config.scheduler.enabled then
    local scheduler = require("codetyper.core.scheduler.scheduler")
    scheduler.start(M.config.scheduler)
  end

  M._initialized = true

  -- Auto-open Ask panel after a short delay (to let UI settle)
  if M.config.auto_open_ask then
    vim.defer_fn(function()
      local ask = require("codetyper.features.ask.engine")
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
