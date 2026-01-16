---@mod codetyper.prompts.agents.linter Linter prompts
local M = {}

M.fix_request = [[
Fix the following linter errors in this code:

ERRORS:
%s

CODE (lines %d-%d):
%s]]

return M
