---@mod codetyper.prompts.agent.scheduler Scheduler prompts
local M = {}

M.retry_context = [[
You requested more context for this task.
Here is the additional information:
%s

Please restart the task with this new context.
]]

return M
