---@mod codetyper.prompts.agents.linter (DEPRECATED)
---
--- Linter prompts migrated to Python agent. This shim provides
--- backward-compatible placeholders.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Linter prompts are managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

M.fix_request = PLACEHOLDER

return M
