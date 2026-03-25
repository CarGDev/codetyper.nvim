---@mod codetyper.agent.diff_review Diff review UI for agent changes
---
--- Provides a lazygit-style window interface for reviewing all changes
--- made during an agent session.

local M = {}

local get_config_utils = require("codetyper.utils.get_config")

M.clear = get_config_utils.clear_diff_entries
M.add = get_config_utils.add_diff_entry
M.get_entries = get_config_utils.get_diff_entries
M.count = get_config_utils.count_diff_entries
M.next = require("codetyper.adapters.nvim.ui.diff_review.navigate_next")
M.prev = require("codetyper.adapters.nvim.ui.diff_review.navigate_prev")
M.approve_current = require("codetyper.adapters.nvim.ui.diff_review.approve_current")
M.reject_current = require("codetyper.adapters.nvim.ui.diff_review.reject_current")
M.approve_all = require("codetyper.adapters.nvim.ui.diff_review.approve_all")
M.apply_approved = require("codetyper.adapters.nvim.ui.diff_review.apply_approved")
M.close = require("codetyper.adapters.nvim.ui.diff_review.close")
M.is_open = require("codetyper.adapters.nvim.ui.diff_review.is_open")
M.open = require("codetyper.adapters.nvim.ui.diff_review.open")

return M
