---@mod codetyper.prompts.agents.intent (DEPRECATED)
---
--- Intent modifiers migrated to Python agent. This shim provides
--- backward-compatible placeholders.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Intent prompts are managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

-- Provide empty modifiers table for backward compatibility
M.modifiers = setmetatable({}, { __index = function() return PLACEHOLDER end })

return M
