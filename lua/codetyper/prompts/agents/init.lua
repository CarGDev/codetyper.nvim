---@mod codetyper.prompts.agents.init (DEPRECATED)
---
--- Agent-mode prompts were migrated to the Python agent. This shim provides
--- minimal placeholders to avoid breaking require() calls in Lua.
--- Functions return empty strings to avoid polluting actual prompts.

local M = setmetatable({}, { __index = function() return "" end })

M.system = ""
M.tool_instructions = ""
M.tool_instructions_text = ""
M.initial_assistant_message = "I've reviewed the provided files. What would you like me to do?"
M.completion = ""
M.text_user_prefix = "User: "
M.text_assistant_prefix = "Assistant: "

--- Build system prompt (returns empty - prompts come from personas or Python agent)
---@return string
function M.build_system_prompt()
  return ""
end

--- Format file context for agent (returns placeholder if used)
---@param files string[] File paths
---@return string
function M.format_file_context(files)
  if not files or #files == 0 then
    return ""
  end
  -- Provide minimal formatting if called
  local parts = { "Files for context:" }
  for _, f in ipairs(files) do
    table.insert(parts, "- " .. f)
  end
  return table.concat(parts, "\n")
end

return M
