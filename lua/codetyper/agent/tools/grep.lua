---@mod codetyper.agent.tools.grep Search tool
---@brief [[
--- Tool for searching file contents using ripgrep.
---@brief ]]

local Base = require("codetyper.agent.tools.base")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "grep"

M.description = [[Searches for a pattern in files using ripgrep.

Returns file paths and matching lines. Use this to find code by content.

Example patterns:
- "function foo" - Find function definitions
- "import.*react" - Find React imports
- "TODO|FIXME" - Find todo comments]]

M.params = {
	{
		name = "pattern",
		description = "Regular expression pattern to search for",
		type = "string",
	},
	{
		name = "path",
		description = "Directory or file to search in (default: project root)",
		type = "string",
		optional = true,
	},
	{
		name = "include",
		description = "File glob pattern to include (e.g., '*.lua')",
		type = "string",
		optional = true,
	},
	{
		name = "max_results",
		description = "Maximum number of results (default: 50)",
		type = "integer",
		optional = true,
	},
}

M.returns = {
	{
		name = "matches",
		description = "JSON array of matches with file, line_number, and content",
		type = "string",
	},
	{
		name = "error",
		description = "Error message if search failed",
		type = "string",
		optional = true,
	},
}

M.requires_confirmation = false

---@param input {pattern: string, path?: string, include?: string, max_results?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	if not input.pattern then
		return nil, "pattern is required"
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Searching for: " .. input.pattern)
	end

	-- Build ripgrep command
	local path = input.path or vim.fn.getcwd()
	local max_results = input.max_results or 50

	-- Resolve path
	if not vim.startswith(path, "/") then
		path = vim.fn.getcwd() .. "/" .. path
	end

	-- Check if ripgrep is available
	if vim.fn.executable("rg") ~= 1 then
		return nil, "ripgrep (rg) is not installed"
	end

	-- Build command args
	local args = {
		"--json",
		"--max-count",
		tostring(max_results),
		"--no-heading",
	}

	if input.include then
		table.insert(args, "--glob")
		table.insert(args, input.include)
	end

	table.insert(args, input.pattern)
	table.insert(args, path)

	-- Execute ripgrep
	local Job = require("plenary.job")
	local job = Job:new({
		command = "rg",
		args = args,
		cwd = vim.fn.getcwd(),
	})

	job:sync(30000) -- 30 second timeout

	local results = job:result() or {}
	local matches = {}

	-- Parse JSON output
	for _, line in ipairs(results) do
		if line and line ~= "" then
			local ok, parsed = pcall(vim.json.decode, line)
			if ok and parsed.type == "match" then
				local data = parsed.data
				table.insert(matches, {
					file = data.path.text,
					line_number = data.line_number,
					content = data.lines.text:gsub("\n$", ""),
				})
			end
		end
	end

	-- Return as JSON
	local result = vim.json.encode({
		matches = matches,
		total = #matches,
		truncated = #matches >= max_results,
	})

	if opts.on_complete then
		opts.on_complete(result, nil)
	end

	return result, nil
end

return M
