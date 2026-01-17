---@mod codetyper.prompts.ask (DEPRECATED)
---
--- All ask-mode prompts have been migrated to the Python agent. This file
--- is a lightweight compatibility shim that returns a stable placeholder
--- for any prompt lookup.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Ask prompts are now managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })
return M
