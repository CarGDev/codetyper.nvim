local M = {}

M.params = {
	{
		name = "path",
		description = "Path to the file to write",
		type = "string",
	},
	{
		name = "content",
		description = "Content to write to the file",
		type = "string",
	},
}

M.returns = {
	{
		name = "success",
		description = "Whether the file was written successfully",
		type = "boolean",
	},
	{
		name = "error",
		description = "Error message if write failed",
		type = "string",
		optional = true,
	},
}

return M