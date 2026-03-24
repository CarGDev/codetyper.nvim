local M = {}

--- Inject code for refactor (replace entire file)
---@param bufnr number Buffer number
---@param code string Generated code
function M.inject_refactor(bufnr, code)
  local lines = vim.split(code, "\n", { plain = true })

  -- Save cursor position
  local cursor = nil
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    cursor = vim.api.nvim_win_get_cursor(wins[1])
  end

  -- Replace buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Restore cursor position if possible
  if cursor then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    cursor[1] = math.min(cursor[1], line_count)
    pcall(vim.api.nvim_win_set_cursor, wins[1], cursor)
  end

  utils.notify("Code refactored", vim.log.levels.INFO)
end

return M
