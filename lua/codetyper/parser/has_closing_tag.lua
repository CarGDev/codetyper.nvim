local utils = require("codetyper.support.utils")
local logger = require("codetyper.support.logger")

--- Check if line contains a closing tag
---@param line string Line to check
---@param close_tag string Closing tag
---@return boolean
local function has_closing_tag(line, close_tag)
  logger.func_entry("parser", "has_closing_tag", { line_preview = line:sub(1, 30), close_tag = close_tag })

  local result = line:find(utils.escape_pattern(close_tag)) ~= nil

  logger.debug("parser", "has_closing_tag: result=" .. tostring(result))
  logger.func_exit("parser", "has_closing_tag", result)

  return result
end

return has_closing_tag
