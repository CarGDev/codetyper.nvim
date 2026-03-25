local logger = require("codetyper.support.logger")
local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")

--- Get the last closed prompt in buffer
---@param bufnr? number Buffer number (default: current)
---@return CoderPrompt|nil Last prompt or nil
local function get_last_prompt(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  logger.func_entry("parser", "get_last_prompt", { bufnr = bufnr })

  local prompts = find_prompts_in_buffer(bufnr)

  if #prompts > 0 then
    local last = prompts[#prompts]
    logger.debug("parser", "get_last_prompt: returning prompt at line " .. last.start_line)
    logger.func_exit("parser", "get_last_prompt", "prompt at line " .. last.start_line)
    return last
  end

  logger.debug("parser", "get_last_prompt: no prompts found")
  logger.func_exit("parser", "get_last_prompt", nil)
  return nil
end

return get_last_prompt
