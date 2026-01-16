---@mod codetyper.params.agent.conflict Parameters for conflict resolution
local M = {}

--- Configuration defaults
M.config = {
	-- Run linter check after accepting AI suggestions
	lint_after_accept = true,
	-- Auto-fix lint errors without prompting
	auto_fix_lint_errors = true,
	-- Auto-show menu after injecting conflict
	auto_show_menu = true,
	-- Auto-show menu for next conflict after resolving one
	auto_show_next_menu = true,
}

--- Highlight groups
M.hl_groups = {
	current = "CoderConflictCurrent",
	current_label = "CoderConflictCurrentLabel",
	incoming = "CoderConflictIncoming",
	incoming_label = "CoderConflictIncomingLabel",
	separator = "CoderConflictSeparator",
	hint = "CoderConflictHint",
}

--- Conflict markers
M.markers = {
	current_start = "<<<<<<< CURRENT",
	separator = "=======",
	incoming_end = ">>>>>>> INCOMING",
}

return M
