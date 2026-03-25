local logger = require("codetyper.support.logger")

--- Get the word being typed after @ symbol
---@param bufnr? number Buffer number
---@return string|nil prefix The text after @ being typed, or nil if not typing a file ref
local function get_file_ref_prefix(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  logger.func_entry("parser", "get_file_ref_prefix", { bufnr = bufnr })

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    logger.debug("parser", "get_file_ref_prefix: no line at cursor")
    logger.func_exit("parser", "get_file_ref_prefix", nil)
    return nil
  end

  local col = cursor[2]
  local before_cursor = line:sub(1, col)

  local prefix = before_cursor:match("@([%w%._%-/]*)$")

  if prefix and before_cursor:sub(-2) == "@/" then
    logger.debug("parser", "get_file_ref_prefix: closing tag detected, returning nil")
    logger.func_exit("parser", "get_file_ref_prefix", nil)
    return nil
  end

  logger.debug("parser", "get_file_ref_prefix: prefix=" .. tostring(prefix))
  logger.func_exit("parser", "get_file_ref_prefix", prefix)

  return prefix
end

return get_file_ref_prefix
