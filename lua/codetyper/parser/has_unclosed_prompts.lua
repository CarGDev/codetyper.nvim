local utils = require("codetyper.support.utils")
local logger = require("codetyper.support.logger")
local get_config = require("codetyper.utils.get_config").get_config

--- Check if buffer has any unclosed prompts
---@param bufnr? number Buffer number (default: current)
---@return boolean
local function has_unclosed_prompts(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  logger.func_entry("parser", "has_unclosed_prompts", { bufnr = bufnr })

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  local cfg = get_config()
  local escaped_open = utils.escape_pattern(cfg.patterns.open_tag)
  local escaped_close = utils.escape_pattern(cfg.patterns.close_tag)

  local _, open_count = content:gsub(escaped_open, "")
  local _, close_count = content:gsub(escaped_close, "")

  local has_unclosed = open_count > close_count

  logger.debug(
    "parser",
    "has_unclosed_prompts: open=" .. open_count .. ", close=" .. close_count .. ", unclosed=" .. tostring(has_unclosed)
  )
  logger.func_exit("parser", "has_unclosed_prompts", has_unclosed)

  return has_unclosed
end

return has_unclosed_prompts
