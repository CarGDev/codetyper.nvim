local logger = require("codetyper.support.logger")
local get_config = require("codetyper.utils.get_config").get_config
local find_prompts = require("codetyper.parser.find_prompts")

--- Find prompts in a buffer
---@param bufnr number Buffer number
---@return CoderPrompt[] List of found prompts
local function find_prompts_in_buffer(bufnr)
  logger.func_entry("parser", "find_prompts_in_buffer", { bufnr = bufnr })

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  logger.debug(
    "parser",
    "find_prompts_in_buffer: bufnr=" .. bufnr .. ", lines=" .. #lines .. ", content_length=" .. #content
  )

  local cfg = get_config()
  local result = find_prompts(content, cfg.patterns.open_tag, cfg.patterns.close_tag)

  logger.func_exit("parser", "find_prompts_in_buffer", "found " .. #result .. " prompts")
  return result
end

return find_prompts_in_buffer
