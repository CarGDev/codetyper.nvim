---@mod codetyper.agent.logs Real-time logging for agent operations
---
--- Captures and displays the agent's thinking process, token usage, and LLM info.

local M = {}

M.log = require("codetyper.adapters.nvim.ui.logs.log")
M.clear = require("codetyper.adapters.nvim.ui.logs.clear")
M.info = require("codetyper.adapters.nvim.ui.logs.info")
M.debug = require("codetyper.adapters.nvim.ui.logs.debug")
M.error = require("codetyper.adapters.nvim.ui.logs.error")
M.warning = require("codetyper.adapters.nvim.ui.logs.warning")
M.thinking = require("codetyper.adapters.nvim.ui.logs.thinking")
M.reason = require("codetyper.adapters.nvim.ui.logs.reason")
M.request = require("codetyper.adapters.nvim.ui.logs.request")
M.response = require("codetyper.adapters.nvim.ui.logs.response")
M.tool = require("codetyper.adapters.nvim.ui.logs.tool")
M.add = require("codetyper.adapters.nvim.ui.logs.add")
M.read = require("codetyper.adapters.nvim.ui.logs.read")
M.explore = require("codetyper.adapters.nvim.ui.logs.explore")
M.explore_done = require("codetyper.adapters.nvim.ui.logs.explore_done")
M.update = require("codetyper.adapters.nvim.ui.logs.update")
M.task = require("codetyper.adapters.nvim.ui.logs.task")
M.task_done = require("codetyper.adapters.nvim.ui.logs.task_done")
M.add_listener = require("codetyper.adapters.nvim.ui.logs.add_listener")
M.remove_listener = require("codetyper.adapters.nvim.ui.logs.remove_listener")
M.get_entries = require("codetyper.adapters.nvim.ui.logs.get_entries")
M.get_token_totals = require("codetyper.adapters.nvim.ui.logs.get_token_totals")
M.get_provider_info = require("codetyper.adapters.nvim.ui.logs.get_provider_info")
M.format_entry = require("codetyper.adapters.nvim.ui.logs.format_entry")
M.format_for_chat = require("codetyper.adapters.nvim.ui.logs.format_for_chat")
M.estimate_tokens = require("codetyper.utils.estimate_tokens")

return M
