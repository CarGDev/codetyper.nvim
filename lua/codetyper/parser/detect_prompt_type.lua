local logger = require("codetyper.support.logger")

--- Extract the prompt type from content
---@param content string Prompt content
---@return "refactor" | "add" | "document" | "explain" | "generic" Prompt type
local function detect_prompt_type(content)
  logger.func_entry("parser", "detect_prompt_type", { content_preview = content:sub(1, 50) })

  local lower = content:lower()

  if lower:match("refactor") then
    logger.debug("parser", "detect_prompt_type: detected 'refactor'")
    logger.func_exit("parser", "detect_prompt_type", "refactor")
    return "refactor"
  elseif lower:match("add") or lower:match("create") or lower:match("implement") then
    logger.debug("parser", "detect_prompt_type: detected 'add'")
    logger.func_exit("parser", "detect_prompt_type", "add")
    return "add"
  elseif lower:match("document") or lower:match("comment") or lower:match("jsdoc") then
    logger.debug("parser", "detect_prompt_type: detected 'document'")
    logger.func_exit("parser", "detect_prompt_type", "document")
    return "document"
  elseif lower:match("explain") or lower:match("what") or lower:match("how") then
    logger.debug("parser", "detect_prompt_type: detected 'explain'")
    logger.func_exit("parser", "detect_prompt_type", "explain")
    return "explain"
  end

  logger.debug("parser", "detect_prompt_type: detected 'generic'")
  logger.func_exit("parser", "detect_prompt_type", "generic")
  return "generic"
end

return detect_prompt_type
