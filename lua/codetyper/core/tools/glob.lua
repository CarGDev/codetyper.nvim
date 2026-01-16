---@mod codetyper.agent.tools.glob File pattern matching tool
---@brief [[
--- Tool for finding files by glob pattern.
---@brief ]]

local Base = require("codetyper.core.tools.base")

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
	if not input.pattern then
		return nil, "pattern is required"
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Finding files: " .. input.pattern)
	end

	-- Resolve base path
	local base_path = input.path or vim.fn.getcwd()
	if not vim.startswith(base_path, "/") then
		base_path = vim.fn.getcwd() .. "/" .. base_path
	end

	local max_results = input.max_results or 100

	-- Use vim.fn.glob or fd if available
	local matches = {}

	if vim.fn.executable("fd") == 1 then
		-- Use fd for better performance
		local Job = require("plenary.job")

		-- Convert glob to fd pattern
		local fd_pattern = input.pattern:gsub("%*%*/", ""):gsub("%*", ".*")

		local job = Job:new({
			command = "fd",
			args = {
				"--type",
				"f",
				"--max-results",
				tostring(max_results),
				"--glob",
				input.pattern,
				base_path,
			},
			cwd = base_path,
		})

		job:sync(30000)
		matches = job:result() or {}
	else
		-- Fallback to vim.fn.globpath
		local pattern = base_path .. "/" .. input.pattern
		local files = vim.fn.glob(pattern, false, true)

		for i, file in ipairs(files) do
			if i > max_results then
				break
			end
			-- Make paths relative to base_path
			local relative = file:gsub("^" .. vim.pesc(base_path) .. "/", "")
			table.insert(matches, relative)
		end
	end

	-- Clean up matches
	local cleaned = {}
	for _, match in ipairs(matches) do
		if match and match ~= "" then
			-- Make relative if absolute
			local relative = match
			if vim.startswith(match, base_path) then
				relative = match:sub(#base_path + 2)
			end
			table.insert(cleaned, relative)
		end
	end

	-- Return as JSON
	local result = vim.json.encode({
		matches = cleaned,
		total = #cleaned,
		truncated = #cleaned >= max_results,
	})

	if opts.on_complete then
		opts.on_complete(result, nil)
	end

	return result, nil
end

return M
