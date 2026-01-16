---@mod codetyper.params.agent.tools Tool definitions
local M = {}

--- Tool definitions in a provider-agnostic format
M.definitions = {
	read_file = {
		name = "read_file",
		description = "Read the contents of a file at the specified path",
		parameters = {
			type = "object",
			properties = {
				path = {
					type = "string",
					description = "The path to the file to read",
				},
				start_line = {
					type = "number",
					description = "Optional start line number (1-indexed)",
				},
				end_line = {
					type = "number",
					description = "Optional end line number (1-indexed)",
				},
			},
			required = { "path" },
		},
	},

	edit_file = {
		name = "edit_file",
		description = "Edit a file by replacing specific content. Provide the exact content to find and the replacement.",
		parameters = {
			type = "object",
			properties = {
				path = {
					type = "string",
					description = "The path to the file to edit",
				},
				find = {
					type = "string",
					description = "The exact content to replace",
				},
				replace = {
					type = "string",
					description = "The new content",
				},
			},
			required = { "path", "find", "replace" },
		},
	},

	write_file = {
		name = "write_file",
		description = "Write content to a file, creating it if it doesn't exist or overwriting if it does",
		parameters = {
			type = "object",
			properties = {
				path = {
					type = "string",
					description = "The path to the file to write",
				},
				content = {
					type = "string",
					description = "The content to write",
				},
			},
			required = { "path", "content" },
		},
	},

	bash = {
		name = "bash",
		description = "Execute a bash command and return the output. Use for git, npm, build tools, etc.",
		parameters = {
			type = "object",
			properties = {
				command = {
					type = "string",
					description = "The bash command to execute",
				},
			},
			required = { "command" },
		},
	},

	delete_file = {
		name = "delete_file",
		description = "Delete a file",
		parameters = {
			type = "object",
			properties = {
				path = {
					type = "string",
					description = "The path to the file to delete",
				},
				reason = {
					type = "string",
					description = "Reason for deletion",
				},
			},
			required = { "path", "reason" },
		},
	},

	list_directory = {
		name = "list_directory",
		description = "List files and directories in a path",
		parameters = {
			type = "object",
			properties = {
				path = {
					type = "string",
					description = "The path to list",
				},
				recursive = {
					type = "boolean",
					description = "Whether to list recursively",
				},
			},
			required = { "path" },
		},
	},

	search_files = {
		name = "search_files",
		description = "Search for files by name/glob pattern or content",
		parameters = {
			type = "object",
			properties = {
				pattern = {
					type = "string",
					description = "Glob pattern to search for filenames",
				},
				content = {
					type = "string",
					description = "Content string to search for within files",
				},
				path = {
					type = "string",
					description = "The root path to start search",
				},
			},
		},
	},
}

return M
