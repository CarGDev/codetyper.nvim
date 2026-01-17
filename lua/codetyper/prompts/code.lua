---@mod codetyper.prompts.code (DEPRECATED)
---
--- Code prompt templates migrated to the Python agent. Compatibility shim.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Code prompts are now managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

M.create_function = PLACEHOLDER
M.complete_function = PLACEHOLDER
M.create_class = PLACEHOLDER
M.modify_class = PLACEHOLDER
M.implement_interface = PLACEHOLDER
M.create_react_component = PLACEHOLDER
M.create_api_endpoint = PLACEHOLDER
M.create_utility = PLACEHOLDER
M.generic = PLACEHOLDER

return M
