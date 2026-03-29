local M = {}
local utils = require("codetyper.support.utils")
local inject_add = require("codetyper.inject.inject_add")

--- Inject documentation
---@param bufnr number Buffer number
---@param code string Generated documentation
function M.inject_document(bufnr, code)
  -- Documentation typically goes above the current function/class
  -- For simplicity, insert at cursor position
  inject_add(bufnr, code)
  utils.notify("Documentation added", vim.log.levels.INFO)
end

return M
