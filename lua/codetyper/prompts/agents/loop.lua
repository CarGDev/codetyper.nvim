---@mod codetyper.prompts.agents.loop (DEPRECATED)
---
--- Agent loop system prompts migrated to Python agent. This shim provides
--- backward-compatible placeholders.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Loop prompts are managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

M.default_system_prompt = PLACEHOLDER
M.dispatch_prompt = PLACEHOLDER

return M
