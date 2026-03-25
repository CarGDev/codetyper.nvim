local logger = require("codetyper.support.logger")

--- Remove file references from prompt content (for clean prompt text)
---@param content string Prompt content
---@return string Cleaned content without file references
local function strip_file_references(content)
  logger.func_entry("parser", "strip_file_references", { content_length = #content })

  local result = content:gsub("@([%w%._%-][%w%._%-/]*)", "")

  logger.debug("parser", "strip_file_references: stripped " .. (#content - #result) .. " chars")
  logger.func_exit("parser", "strip_file_references", "length=" .. #result)

  return result
end

return strip_file_references
