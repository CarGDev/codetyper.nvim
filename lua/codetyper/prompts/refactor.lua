---@mod codetyper.prompts.refactor (DEPRECATED)
---
--- Refactor prompts migrated to the Python agent. Compatibility shim.

local PLACEHOLDER = "[PROMPTS_MOVED_TO_AGENT] Refactor prompts are now managed by the Python agent."
local M = setmetatable({}, { __index = function() return PLACEHOLDER end })

M.general = PLACEHOLDER
M.extract_function = PLACEHOLDER
M.simplify = PLACEHOLDER
M.async_await = PLACEHOLDER
M.add_error_handling = PLACEHOLDER
M.optimize_performance = PLACEHOLDER
M.convert_to_typescript = PLACEHOLDER
M.apply_pattern = PLACEHOLDER
M.split_function = PLACEHOLDER
M.remove_code_smells = PLACEHOLDER

return M
