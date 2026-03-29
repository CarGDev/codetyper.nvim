local M = {}
local utils = require("codetyper.support.utils")
local inject_refactor = require("codetyper.inject.inject_refactor")
local inject_add = require("codetyper.inject.inject_add")

--- Generic injection (prompt user for action)
---@param bufnr number Buffer number
---@param code string Generated code
function M.inject_generic(bufnr, code)
  local actions = {
    "Replace entire file",
    "Insert at cursor",
    "Append to end",
    "Copy to clipboard",
    "Cancel",
  }

  vim.ui.select(actions, {
    prompt = "How to inject the generated code?",
  }, function(choice)
    if not choice then
      return
    end

    if choice == "Replace entire file" then
      inject_refactor(bufnr, code)
    elseif choice == "Insert at cursor" then
      inject_add(bufnr, code)
    elseif choice == "Append to end" then
      local lines = vim.split(code, "\n", { plain = true })
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
      utils.notify("Code appended to end", vim.log.levels.INFO)
    elseif choice == "Copy to clipboard" then
      vim.fn.setreg("+", code)
      utils.notify("Code copied to clipboard", vim.log.levels.INFO)
    end
  end)
end

return M
