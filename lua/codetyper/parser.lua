---@mod codetyper.parser Parser for /@ @/ prompt tags

local M = {}

local utils = require("codetyper.utils")

--- Find all prompts in buffer content
---@param content string Buffer content
---@param open_tag string Opening tag
---@param close_tag string Closing tag
---@return CoderPrompt[] List of found prompts
function M.find_prompts(content, open_tag, close_tag)
  local prompts = {}
  local escaped_open = utils.escape_pattern(open_tag)
  local escaped_close = utils.escape_pattern(close_tag)

  local lines = vim.split(content, "\n", { plain = true })
  local in_prompt = false
  local current_prompt = nil
  local prompt_content = {}

  for line_num, line in ipairs(lines) do
    if not in_prompt then
      -- Look for opening tag
      local start_col = line:find(escaped_open)
      if start_col then
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
        in_prompt = false
        current_prompt = nil
        prompt_content = {}
      else
        table.insert(prompt_content, line)
      end
    end
  end

  return prompts
end

--- Find prompts in a buffer
---@param bufnr number Buffer number
---@return CoderPrompt[] List of found prompts
function M.find_prompts_in_buffer(bufnr)
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  return M.find_prompts(content, config.patterns.open_tag, config.patterns.close_tag)
end

--- Get prompt at cursor position
---@param bufnr? number Buffer number (default: current)
---@return CoderPrompt|nil Prompt at cursor or nil
function M.get_prompt_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2] + 1 -- Convert to 1-indexed

  local prompts = M.find_prompts_in_buffer(bufnr)

  for _, prompt in ipairs(prompts) do
    if line >= prompt.start_line and line <= prompt.end_line then
      if line == prompt.start_line and col < prompt.start_col then
        goto continue
      end
      if line == prompt.end_line and col > prompt.end_col then
        goto continue
      end
      return prompt
    end
    ::continue::
  end

  return nil
end

--- Get the last closed prompt in buffer
---@param bufnr? number Buffer number (default: current)
---@return CoderPrompt|nil Last prompt or nil
function M.get_last_prompt(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local prompts = M.find_prompts_in_buffer(bufnr)

  if #prompts > 0 then
    return prompts[#prompts]
  end

  return nil
end

--- Extract the prompt type from content
---@param content string Prompt content
---@return "refactor" | "add" | "document" | "explain" | "generic" Prompt type
function M.detect_prompt_type(content)
  local lower = content:lower()

  if lower:match("refactor") then
    return "refactor"
  elseif lower:match("add") or lower:match("create") or lower:match("implement") then
    return "add"
  elseif lower:match("document") or lower:match("comment") or lower:match("jsdoc") then
    return "document"
  elseif lower:match("explain") or lower:match("what") or lower:match("how") then
    return "explain"
  end

  return "generic"
end

--- Clean prompt content (trim whitespace, normalize newlines)
---@param content string Raw prompt content
---@return string Cleaned content
function M.clean_prompt(content)
  -- Trim leading/trailing whitespace
  content = content:match("^%s*(.-)%s*$")
  -- Normalize multiple newlines
  content = content:gsub("\n\n\n+", "\n\n")
  return content
end

--- Check if line contains a closing tag
---@param line string Line to check
---@param close_tag string Closing tag
---@return boolean
function M.has_closing_tag(line, close_tag)
  return line:find(utils.escape_pattern(close_tag)) ~= nil
end

--- Check if buffer has any unclosed prompts
---@param bufnr? number Buffer number (default: current)
---@return boolean
function M.has_unclosed_prompts(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  local escaped_open = utils.escape_pattern(config.patterns.open_tag)
  local escaped_close = utils.escape_pattern(config.patterns.close_tag)

  local _, open_count = content:gsub(escaped_open, "")
  local _, close_count = content:gsub(escaped_close, "")

  return open_count > close_count
end

return M
