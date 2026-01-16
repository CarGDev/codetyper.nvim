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

return M
