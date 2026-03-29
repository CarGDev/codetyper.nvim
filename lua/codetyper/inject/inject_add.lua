local M = {}
local utils = require("codetyper.support.utils")

--- Inject code for add (append at cursor or end)
---@param bufnr number Buffer number
---@param code string Generated code
function M.inject_add(bufnr, code)
  local lines = vim.split(code, "\n", { plain = true })

  -- Try to find a window displaying this buffer to get cursor position
  local insert_line
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    local cursor = vim.api.nvim_win_get_cursor(wins[1])
    insert_line = cursor[1]
  else
    insert_line = vim.api.nvim_buf_line_count(bufnr)
  end

  -- Insert lines at position
  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, lines)

  utils.notify("Code added at line " .. (insert_line + 1), vim.log.levels.INFO)
end

return M
