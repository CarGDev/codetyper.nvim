local M = {}
--- Inject code with strategy and range (used by patch system)
---@param bufnr number Buffer number
---@param code string Generated code
---@param opts table|nil { strategy = "replace"|"insert"|"append", range = { start_line, end_line } (1-based) }
---@return table { imports_added: number, body_lines: number, imports_merged: boolean }
function M.inject(bufnr, code, opts)
  opts = opts or {}
  local strategy = opts.strategy or "replace"
  local range = opts.range
  local lines = vim.split(code, "\n", { plain = true })
  local body_lines = #lines

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return { imports_added = 0, body_lines = 0, imports_merged = false }
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  if strategy == "replace" and range and range.start_line and range.end_line then
    local start_0 = math.max(0, range.start_line - 1)
    local end_0 = math.min(line_count, range.end_line)
    if end_0 < start_0 then
      end_0 = start_0
    end
    vim.api.nvim_buf_set_lines(bufnr, start_0, end_0, false, lines)
  elseif strategy == "insert" and range and range.start_line then
    local at_0 = math.max(0, math.min(range.start_line - 1, line_count))
    vim.api.nvim_buf_set_lines(bufnr, at_0, at_0, false, lines)
  else
    -- append
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
  end

  return { imports_added = 0, body_lines = body_lines, imports_merged = false }
end

return M
