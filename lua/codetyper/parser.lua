---@mod codetyper.parser Simplified parser delegating to detector modules
---
--- The tag detection and range extraction were migrated to dedicated
--- detector modules under lua/codetyper/detector/. This parser now
--- provides a thin compatibility layer that exposes the previous API
--- but delegates all structural work to the detectors.

local M = {}

local detectors = {
  inline = require("codetyper.detector.inline_tags"),
  ranges = require("codetyper.detector.ranges"),
  triggers = require("codetyper.detector.triggers"),
}

--- Find prompts in arbitrary content
---@param content string
---@param open_tag string
---@param close_tag string
---@return table[] tags
function M.find_prompts(content, open_tag, close_tag)
  open_tag = open_tag or "/@"
  close_tag = close_tag or "@/"
  return detectors.inline.detect_tags(content, open_tag, close_tag)
end

--- Find prompts in a buffer
---@param bufnr number
---@return table[] tags
function M.find_prompts_in_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  return M.find_prompts(content)
end

--- Get prompt at cursor position
---@param bufnr number
---@return table|nil tag
function M.get_prompt_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local tags = M.find_prompts_in_buffer(bufnr)
  for _, t in ipairs(tags) do
    if row >= t.start_line and row <= t.end_line then
      if (row > t.start_line or col + 1 >= t.start_col) and (row < t.end_line or col + 1 <= t.end_col) then
        return t
      end
    end
  end
  return nil
end

--- Get the last closed prompt in buffer
---@param bufnr number
---@return table|nil tag
function M.get_last_prompt(bufnr)
  local tags = M.find_prompts_in_buffer(bufnr)
  if #tags > 0 then
    return tags[#tags]
  end
  return nil
end

--- Deprecated: content-based prompt type detection
--- This logic is intentionally minimal; intent detection moved to the agent.
---@param content string
---@return string
function M.detect_prompt_type(content)
  return "generic"
end

--- Clean prompt content (trim whitespace, normalize newlines)
---@param content string
---@return string
function M.clean_prompt(content)
  if not content then return "" end
  content = content:match("^%s*(.-)%s*$") or content
  content = content:gsub("\n\n\n+", "\n\n")
  return content
end

--- Check if a line contains a closing tag
---@param line string
---@param close_tag string
---@return boolean
function M.has_closing_tag(line, close_tag)
  close_tag = close_tag or "@/"
  return line:find(vim.pesc(close_tag)) ~= nil
end

--- Check if buffer has any unclosed prompts
---@param bufnr number
---@return boolean
function M.has_unclosed_prompts(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local tags = M.find_prompts_in_buffer(bufnr)
  -- If there is any tag missing an end_line, consider it unclosed
  for _, t in ipairs(tags) do
    if not t.end_line then
      return true
    end
  end
  return false
end

--- Extract file references from prompt content
---@param content string
---@return string[]
function M.extract_file_references(content)
  local files = {}
  if not content then return files end
  for file in content:gmatch("@([w._-][w._-/]*)") do
    if file ~= "" then table.insert(files, file) end
  end
  return files
end

--- Remove file references from prompt content
---@param content string
---@return string
function M.strip_file_references(content)
  if not content then return content end
  return content:gsub("@([w._-][w._-/]*)", "")
end

--- Check if cursor is inside an open tag
---@param bufnr number
---@return boolean, number?
function M.is_cursor_in_open_tag(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local tags = M.find_prompts_in_buffer(bufnr)
  local open_line = nil
  local open_count = 0
  local close_count = 0
  for _, t in ipairs(tags) do
    if t.start_line and t.start_line <= row then
      open_count = open_count + 1
      open_line = t.start_line
    end
    if t.end_line and t.end_line <= row then
      close_count = close_count + 1
    end
  end
  local is_inside = open_count > close_count
  return is_inside, is_inside and open_line or nil
end

--- Get the word being typed after @ symbol
---@param bufnr number
---@return string|nil
function M.get_file_ref_prefix(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then return nil end
  local col = cursor[2]
  local before_cursor = line:sub(1, col)
  local prefix = before_cursor:match("@([w._-/]*)$")
  if prefix and before_cursor:sub(-2) == "@/" then return nil end
  return prefix
end

return M
