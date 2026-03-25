local logger = require("codetyper.support.logger")

--- Extract file references from prompt content
--- Matches @filename patterns but NOT @/ (closing tag)
---@param content string Prompt content
---@return string[] List of file references
local function extract_file_references(content)
  logger.func_entry("parser", "extract_file_references", { content_length = #content })

  local files = {}
  for file in content:gmatch("@([%w%._%-][%w%._%-/]*)") do
    if file ~= "" then
      table.insert(files, file)
      logger.debug("parser", "extract_file_references: found file reference: " .. file)
    end
  end

  logger.debug("parser", "extract_file_references: found " .. #files .. " file references")
  logger.func_exit("parser", "extract_file_references", files)

  return files
end

return extract_file_references
