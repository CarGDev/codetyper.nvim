---@mod codetyper.prompts.agents.tools (DEPRECATED)
---
--- Tool instruction prompts migrated to Python agent. This shim provides
--- backward-compatible placeholders.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Tool instructions are managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

M.instructions = setmetatable({}, { __index = function() return PLACEHOLDER end })

return M
