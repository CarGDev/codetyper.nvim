--- Create extmarks for injection range so position survives user edits
---@param target_bufnr number Target buffer (where code will be injected)
---@param range { start_line: number, end_line: number } Range to mark (1-based)
---@return table|nil injection_marks { start_mark, end_mark } or nil if buffer invalid
local function create_injection_marks(target_bufnr, range)
  if not range or target_bufnr == -1 or not vim.api.nvim_buf_is_valid(target_bufnr) then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(target_bufnr)
  if line_count == 0 then
    return nil
  end
  local start_line = math.max(1, math.min(range.start_line, line_count))
  local end_line = math.max(1, math.min(range.end_line, line_count))
  if start_line > end_line then
    end_line = start_line
  end
  local marks = require("codetyper.core.marks")
  local end_line_content = vim.api.nvim_buf_get_lines(target_bufnr, end_line - 1, end_line, false)
  local end_col_0 = 0
  if end_line_content and end_line_content[1] then
    end_col_0 = #end_line_content[1]
  end
  local start_mark, end_mark = marks.mark_range(target_bufnr, start_line, end_line, end_col_0)
  if not start_mark.id or not end_mark.id then
    return nil
  end
  return { start_mark = start_mark, end_mark = end_mark }
end

return create_injection_marks
