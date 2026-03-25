local logger = require("codetyper.support.logger")

--- Clean prompt content (trim whitespace, normalize newlines)
---@param content string Raw prompt content
---@return string Cleaned content
local function clean_prompt(content)
  logger.func_entry("parser", "clean_prompt", { content_length = #content })

  -- Trim leading/trailing whitespace
  content = content:match("^%s*(.-)%s*$")
  -- Normalize multiple newlines
  content = content:gsub("\n\n\n+", "\n\n")

  logger.debug("parser", "clean_prompt: cleaned from " .. #content .. " chars")
  logger.func_exit("parser", "clean_prompt", "length=" .. #content)

  return content
end

return clean_prompt
