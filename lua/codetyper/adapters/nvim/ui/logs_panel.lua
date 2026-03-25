---@mod codetyper.logs_panel Standalone logs panel for code generation
---
local M = {}

M.open = require("codetyper.adapters.nvim.ui.logs_panel.open")
M.close = require("codetyper.adapters.nvim.ui.logs_panel.close")
M.toggle = require("codetyper.adapters.nvim.ui.logs_panel.toggle")
M.is_open = require("codetyper.adapters.nvim.ui.logs_panel.is_open")
M.ensure_open = require("codetyper.adapters.nvim.ui.logs_panel.ensure_open")
M.setup = require("codetyper.adapters.nvim.ui.logs_panel.setup")

return M
