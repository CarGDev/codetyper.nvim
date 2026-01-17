---@mod codetyper.detector.inline_tags
---
--- Detect inline prompt tags (e.g., /@ ... @/). This module only performs
--- syntactic detection and returns tag ranges and raw content. No
--- interpretation or validation is performed here.

local M = {}
local utils = require("codetyper.support.utils")

--- Detect tags in a plain text string
---@param text string
---@param open_tag string
---@param close_tag string
---@return table[] List of tags: {start_line, start_col, end_line, end_col, content, raw}
function M.detect_tags(text, open_tag, close_tag)
  open_tag = open_tag or "/@"
  close_tag = close_tag or "@/"

  local tags = {}
  if not text or text == "" then return tags end

  local lines = vim.split(text, "\n", { plain = true })
  local in_tag = false
  local current = nil
  local buffer = {}

  for i, line in ipairs(lines) do
    if not in_tag then
      local s, e = line:find(open_tag, 1, true)
      if s then
        in_tag = true
        current = {
          start_line = i,
          start_col = s,
          end_line = nil,
          end_col = nil,
          content = "",
          raw = "",
        }
        local after = line:sub(e + 1)
        local cs, ce = after:find(close_tag, 1, true)
        if cs then
          -- Single line tag
          local tag_content = after:sub(1, cs - 1)
          current.content = tag_content
          current.raw = tag_content
          current.end_line = i
          current.end_col = e + ce
          table.insert(tags, current)
          in_tag = false
          current = nil
        else
          table.insert(buffer, after)
        end
      end
    else
      local cs, ce = line:find(close_tag, 1, true)
      if cs then
        table.insert(buffer, line:sub(1, cs - 1))
        local tag_content = table.concat(buffer, "\n")
        current.content = tag_content
        current.raw = tag_content
        current.end_line = i
        current.end_col = ce
        table.insert(tags, current)
        in_tag = false
        current = nil
        buffer = {}
      else
        table.insert(buffer, line)
      end
    end
  end

  return tags
end

return M
