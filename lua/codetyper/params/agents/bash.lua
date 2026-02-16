M.params = {
	{
		name = "command",
		description = "The shell command to execute",
		type = "string",
	},
	{
		name = "cwd",
		description = "Working directory for the command (optional)",
		type = "string",
		optional = true,
	},
	{
		name = "timeout",
		description = "Timeout in milliseconds (default: 120000)",
		type = "integer",
		optional = true,
	},
}

M.returns = {
	{
		name = "stdout",
		description = "Command output",
		type = "string",
	},
	{
		name = "error",
		description = "Error message if command failed",
		type = "string",
		optional = true,
	},
}

return M
