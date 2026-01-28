---@mod codetyper.agent.tools.grep Search tool
---@brief [[
--- Tool for searching file contents using ripgrep.
---@brief ]]

local Base = require("codetyper.core.tools.base")
local path_utils = require("codetyper.support.path")
local job_utils = require("codetyper.support.job")
local common = require("codetyper.core.tools.common")

local description = require("codetyper.params.agents.grep").description
local params = require("codetyper.prompts.agents.grep").params
local returns = require("codetyper.prompts.agents.grep").returns

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "grep"
M.description = description
M.params = params
M.returns = returns

M.requires_confirmation = false

---@param input {pattern: string, path?: string, include?: string, max_results?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	local valid, err = common.validate_required(input, { "pattern" })
	if not valid then
		return nil, err
	end

	common.log(opts, "Searching for: " .. input.pattern)

	local path = path_utils.resolve(input.path or vim.fn.getcwd())
	local max_results = input.max_results or 50

	local matches, rg_err = job_utils.ripgrep(input.pattern, path, {
		max_results = max_results,
		include = input.include,
	})

	if rg_err then
		return nil, rg_err
	end

	local result = common.json_result(common.list_result(matches, max_results))
	return common.return_result(opts, result, nil)
end

return M
