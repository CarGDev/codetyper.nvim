local M = {}

M.params = {
	{
		name = "path",
		description = "Absolute or relative path to the file to edit",
		type = "string",
	},
	{
		name = "old_string",
		description = "The EXACT text content to find and replace. Must match actual file content. Use view tool first to see exact content. For new files only, use empty string.",
		type = "string",
	},
	{
		name = "new_string",
		description = "The new text that will replace old_string. Include the complete replacement including any unchanged surrounding context.",
		type = "string",
	},
}

M.returns = {
	{
		name = "success",
		description = "Whether the edit was applied successfully",
		type = "boolean",
	},
	{
		name = "error",
		description = "Error message if edit failed (e.g., old_string not found)",
		type = "string",
		optional = true,
	},
}

return M
