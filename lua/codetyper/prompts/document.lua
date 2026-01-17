---@mod codetyper.prompts.document (DEPRECATED)
---
--- Documentation prompts migrated to the Python agent. Compatibility shim.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Documentation prompts are now managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

M.jsdoc = PLACEHOLDER
M.python_docstring = PLACEHOLDER
M.luadoc = PLACEHOLDER
M.godoc = PLACEHOLDER
M.readme = PLACEHOLDER
M.inline_comments = PLACEHOLDER
M.api_docs = PLACEHOLDER
M.type_definitions = PLACEHOLDER
M.changelog = PLACEHOLDER
M.generic = PLACEHOLDER

return M
