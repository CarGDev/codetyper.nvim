---@mod codetyper.detector.ranges
---
--- Extract ranges and provide simple buffer context information.
--- This module is a pure extractor and performs no interpretation.

local M = {}
local utils = require("codetyper.support.utils")

--- Extract content for a detected tag and provide buffer context
---@param bufnr number
---@param tag table Detected tag from inline_tags (start_line, start_col, end_line, end_col, raw)
---@return table {content=string, context={filepath, filetype, cursor_pos, visible_range}}
function M.extract_range(bufnr, tag)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = vim.api.nvim_buf_get_lines(bufnr, tag.start_line - 1, tag.end_line, false)
  -- Trim first/last line to tag columns
  if #lines > 0 then
    lines[1] = lines[1]:sub(tag.start_col + 1) or ""
    lines[#lines] = lines[#lines]:sub(1, tag.end_col - (tag.end_line == tag.start_line and tag.start_col or 0)) or lines[#lines]
  end

  local content = table.concat(lines, "\n")

  local context = {
    filepath = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    cursor_pos = vim.api.nvim_win_get_cursor(0),
    visible_range = { vim.fn.line("w0"), vim.fn.line("w$") },
  }

  return { content = content, context = context }
end

return M
