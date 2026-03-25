local logger = require("codetyper.support.logger")
local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")

--- Get prompt at cursor position
---@param bufnr? number Buffer number (default: current)
---@return CoderPrompt|nil Prompt at cursor or nil
local function get_prompt_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2] + 1 -- Convert to 1-indexed

  logger.func_entry("parser", "get_prompt_at_cursor", {
    bufnr = bufnr,
    line = line,
    col = col,
  })

  local prompts = find_prompts_in_buffer(bufnr)

  logger.debug("parser", "get_prompt_at_cursor: checking " .. #prompts .. " prompts")

  for i, prompt in ipairs(prompts) do
    logger.debug(
      "parser",
      "get_prompt_at_cursor: checking prompt " .. i .. " (lines " .. prompt.start_line .. "-" .. prompt.end_line .. ")"
    )
    if line >= prompt.start_line and line <= prompt.end_line then
      logger.debug("parser", "get_prompt_at_cursor: cursor line " .. line .. " is within prompt line range")
      if line == prompt.start_line and col < prompt.start_col then
        logger.debug(
          "parser",
          "get_prompt_at_cursor: cursor col " .. col .. " is before prompt start_col " .. prompt.start_col
        )
        goto continue
      end
      if line == prompt.end_line and col > prompt.end_col then
        logger.debug(
          "parser",
          "get_prompt_at_cursor: cursor col " .. col .. " is after prompt end_col " .. prompt.end_col
        )
        goto continue
      end
      logger.debug("parser", "get_prompt_at_cursor: found prompt at cursor")
      logger.func_exit("parser", "get_prompt_at_cursor", "prompt found")
      return prompt
    end
    ::continue::
  end

  logger.debug("parser", "get_prompt_at_cursor: no prompt found at cursor")
  logger.func_exit("parser", "get_prompt_at_cursor", nil)
  return nil
end

return get_prompt_at_cursor
