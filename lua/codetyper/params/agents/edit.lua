M.params = {
	{
		name = "path",
		description = "Path to the file to edit",
		type = "string",
	},
	{
		name = "old_string",
		description = "Text to find and replace (empty string to create new file or append)",
		type = "string",
	},
	{
		name = "new_string",
		description = "Text to replace with",
		type = "string",
	},
}

M.returns = {
	{
		name = "success",
		description = "Whether the edit was applied",
		type = "boolean",
	},
	{
		name = "error",
		description = "Error message if edit failed",
		type = "string",
		optional = true,
	},
}

return M
