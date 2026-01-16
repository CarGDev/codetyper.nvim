---@mod codetyper.agent.tools.view File viewing tool
---@brief [[
--- Tool for reading file contents with line range support.
---@brief ]]

local Base = require("codetyper.agent.tools.base")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "view"

M.description = [[Reads the content of a file.

Usage notes:
- Provide the file path relative to the project root
- Use start_line and end_line to read specific sections
- If content is truncated, use line ranges to read in chunks
- Returns JSON with content, total_line_count, and is_truncated]]

M.params = {
	{
		name = "path",
		description = "Path to the file (relative to project root or absolute)",
		type = "string",
	},
	{
		name = "start_line",
		description = "Line number to start reading (1-indexed)",
		type = "integer",
		optional = true,
	},
	{
		name = "end_line",
		description = "Line number to end reading (1-indexed, inclusive)",
		type = "integer",
		optional = true,
	},
}

M.returns = {
	{
		name = "content",
		description = "File contents as JSON with content, total_line_count, is_truncated",
		type = "string",
	},
	{
		name = "error",
		description = "Error message if file could not be read",
		type = "string",
		optional = true,
	},
}

M.requires_confirmation = false

--- Maximum content size before truncation
local MAX_CONTENT_SIZE = 200 * 1024 -- 200KB

---@param input {path: string, start_line?: integer, end_line?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	if not input.path then
		return nil, "path is required"
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Reading file: " .. input.path)
	end

	-- Resolve path
	local path = input.path
	if not vim.startswith(path, "/") then
		-- Relative path - resolve from project root
		local root = vim.fn.getcwd()
		path = root .. "/" .. path
	end

	-- Check if file exists
	local stat = vim.uv.fs_stat(path)
	if not stat then
		return nil, "File not found: " .. input.path
	end

	if stat.type == "directory" then
		return nil, "Path is a directory: " .. input.path
	end

	-- Read file
	local lines = vim.fn.readfile(path)
	if not lines then
		return nil, "Failed to read file: " .. input.path
	end

	-- Apply line range
	local start_line = input.start_line or 1
	local end_line = input.end_line or #lines

	start_line = math.max(1, start_line)
	end_line = math.min(#lines, end_line)

	local total_lines = #lines
	local selected_lines = {}

	for i = start_line, end_line do
		table.insert(selected_lines, lines[i])
	end

	-- Check for truncation
	local content = table.concat(selected_lines, "\n")
	local is_truncated = false

	if #content > MAX_CONTENT_SIZE then
		-- Truncate content
		local truncated_lines = {}
		local size = 0

		for _, line in ipairs(selected_lines) do
			size = size + #line + 1
			if size > MAX_CONTENT_SIZE then
				is_truncated = true
				break
			end
			table.insert(truncated_lines, line)
		end

		content = table.concat(truncated_lines, "\n")
	end

	-- Return as JSON
	local result = vim.json.encode({
		content = content,
		total_line_count = total_lines,
		is_truncated = is_truncated,
		start_line = start_line,
		end_line = end_line,
	})

	if opts.on_complete then
		opts.on_complete(result, nil)
	end

	return result, nil
end

return M
