---@mod codetyper.agent.tools.glob File pattern matching tool
---@brief [[
--- Tool for finding files by glob pattern.
---@brief ]]

local Base = require("codetyper.core.tools.base")
local path_utils = require("codetyper.support.path")
local job_utils = require("codetyper.support.job")
local common = require("codetyper.core.tools.common")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "glob"

M.description = [[Finds files matching a glob pattern.

Example patterns:
- "**/*.lua" - All Lua files
- "src/**/*.ts" - TypeScript files in src
- "**/test_*.py" - Test files in Python]]

M.params = {
	{
		name = "pattern",
		description = "Glob pattern to match files",
		type = "string",
	},
	{
		name = "path",
		description = "Base directory to search in (default: project root)",
		type = "string",
		optional = true,
	},
	{
		name = "max_results",
		description = "Maximum number of results (default: 100)",
		type = "integer",
		optional = true,
	},
}

M.returns = {
	{
		name = "matches",
		description = "JSON array of matching file paths",
		type = "string",
	},
	{
		name = "error",
		description = "Error message if glob failed",
		type = "string",
		optional = true,
	},
}

M.requires_confirmation = false

---@param input {pattern: string, path?: string, max_results?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	local valid, err = common.validate_required(input, { "pattern" })
	if not valid then
		return nil, err
	end

	common.log(opts, "Finding files: " .. input.pattern)

	local base_path = path_utils.resolve(input.path or vim.fn.getcwd())
	local max_results = input.max_results or 100

	local matches = {}

	if vim.fn.executable("fd") == 1 then
		-- Use fd for better performance
		local files, fd_err = job_utils.fd(input.pattern, base_path, {
			max_results = max_results,
		})

		if fd_err then
			return nil, fd_err
		end
		matches = files
	else
		-- Fallback to vim.fn.globpath
		local pattern = base_path .. "/" .. input.pattern
		local files = vim.fn.glob(pattern, false, true)

		for i, file in ipairs(files) do
			if i > max_results then
				break
			end
			local relative = path_utils.make_relative(file, base_path)
			table.insert(matches, relative)
		end
	end

	-- Clean up matches - make relative if absolute
	local cleaned = {}
	for _, match in ipairs(matches) do
		if match and match ~= "" then
			local relative = path_utils.make_relative(match, base_path)
			table.insert(cleaned, relative)
		end
	end

	local result = common.json_result(common.list_result(cleaned, max_results))
	return common.return_result(opts, result, nil)
end

return M
