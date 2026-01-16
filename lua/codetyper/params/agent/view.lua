local M = {}

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

return M