local utils = require("codetyper.support.utils")
local logger = require("codetyper.support.logger")
local get_config = require("codetyper.utils.get_config").get_config

--- Check if cursor is inside an unclosed prompt tag
---@param bufnr? number Buffer number (default: current)
---@return boolean is_inside Whether cursor is inside an open tag
---@return number|nil start_line Line where the open tag starts
local function is_cursor_in_open_tag(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  logger.func_entry("parser", "is_cursor_in_open_tag", { bufnr = bufnr })

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_line, false)
  local cfg = get_config()
  local escaped_open = utils.escape_pattern(cfg.patterns.open_tag)
  local escaped_close = utils.escape_pattern(cfg.patterns.close_tag)

  local open_count = 0
  local close_count = 0
  local last_open_line = nil

  for line_num, line in ipairs(lines) do
    for _ in line:gmatch(escaped_open) do
      open_count = open_count + 1
      last_open_line = line_num
      logger.debug("parser", "is_cursor_in_open_tag: found open tag at line " .. line_num)
    end
    for _ in line:gmatch(escaped_close) do
      close_count = close_count + 1
      logger.debug("parser", "is_cursor_in_open_tag: found close tag at line " .. line_num)
    end
  end

  local is_inside = open_count > close_count

  logger.debug(
    "parser",
    "is_cursor_in_open_tag: open="
      .. open_count
      .. ", close="
      .. close_count
      .. ", is_inside="
      .. tostring(is_inside)
      .. ", last_open_line="
      .. tostring(last_open_line)
  )
  logger.func_exit("parser", "is_cursor_in_open_tag", { is_inside = is_inside, last_open_line = last_open_line })

  return is_inside, is_inside and last_open_line or nil
end

return is_cursor_in_open_tag
