local utils = require("codetyper.support.utils")
local logger = require("codetyper.support.logger")

--- Find all prompts in buffer content
---@param content string Buffer content
---@param open_tag string Opening tag
---@param close_tag string Closing tag
---@return CoderPrompt[] List of found prompts
function find_prompts(content, open_tag, close_tag)
  logger.func_entry("parser", "find_prompts", {
    content_length = #content,
    open_tag = open_tag,
    close_tag = close_tag,
  })

  local prompts = {}
  local escaped_open = utils.escape_pattern(open_tag)
  local escaped_close = utils.escape_pattern(close_tag)

  local lines = vim.split(content, "\n", { plain = true })
  local in_prompt = false
  local current_prompt = nil
  local prompt_content = {}

  logger.debug("parser", "find_prompts: parsing " .. #lines .. " lines")

  for line_num, line in ipairs(lines) do
    if not in_prompt then
      -- Look for opening tag
      local start_col = line:find(escaped_open)
      if start_col then
        logger.debug("parser", "find_prompts: found opening tag at line " .. line_num .. ", col " .. start_col)
        in_prompt = true
        current_prompt = {
          start_line = line_num,
          start_col = start_col,
          content = "",
        }
        -- Get content after opening tag on same line
        local after_tag = line:sub(start_col + #open_tag)
        local end_col = after_tag:find(escaped_close)
        if end_col then
          -- Single line prompt
          current_prompt.content = after_tag:sub(1, end_col - 1)
          current_prompt.end_line = line_num
          current_prompt.end_col = start_col + #open_tag + end_col + #close_tag - 2
          table.insert(prompts, current_prompt)
          logger.debug("parser", "find_prompts: single-line prompt completed at line " .. line_num)
          in_prompt = false
          current_prompt = nil
        else
          table.insert(prompt_content, after_tag)
        end
      end
    else
      -- Look for closing tag
      local end_col = line:find(escaped_close)
      if end_col then
        -- Found closing tag
        local before_tag = line:sub(1, end_col - 1)
        table.insert(prompt_content, before_tag)
        current_prompt.content = table.concat(prompt_content, "\n")
        current_prompt.end_line = line_num
        current_prompt.end_col = end_col + #close_tag - 1
        table.insert(prompts, current_prompt)
        logger.debug(
          "parser",
          "find_prompts: multi-line prompt completed at line " .. line_num .. ", total lines: " .. #prompt_content
        )
        in_prompt = false
        current_prompt = nil
        prompt_content = {}
      else
        table.insert(prompt_content, line)
      end
    end
  end

  logger.debug("parser", "find_prompts: found " .. #prompts .. " prompts total")
  logger.func_exit("parser", "find_prompts", "found " .. #prompts .. " prompts")

  return prompts
end

return find_prompts
