---@mod codetyper.prompts.system (DEPRECATED)
---
--- System prompts were migrated to the Python agent. This shim exposes a
--- minimal set of fields as placeholders so Lua consumers won't error.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] System prompts are managed by the Python agent."
local M = {}

-- Common system prompt templates (placeholders)
M.code_generation = PLACEHOLDER
M.code_generation_simple = PLACEHOLDER
M.ask = PLACEHOLDER
M.explain = PLACEHOLDER
M.refactor = PLACEHOLDER
M.document = PLACEHOLDER
M.test = PLACEHOLDER

return M
