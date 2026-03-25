---@mod codetyper.agent.context_modal Modal for additional context input
---@brief [[
--- Opens a floating window for user to provide additional context
--- when the LLM requests more information.
---@brief ]]

local M = {}

M.close = require("codetyper.adapters.nvim.ui.context_modal.close")
M.is_open = require("codetyper.adapters.nvim.ui.context_modal.is_open")
M.setup = require("codetyper.adapters.nvim.ui.context_modal.setup")
M.open = require("codetyper.adapters.nvim.ui.context_modal.open")

return M
