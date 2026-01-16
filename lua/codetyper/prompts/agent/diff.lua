---@mod codetyper.prompts.agent.diff Prompts and UI strings for diff view and bash approval
local M = {}

--- Bash approval dialog strings
M.bash_approval = {
	title = "  BASH COMMAND APPROVAL",
	divider = "  " .. string.rep("─", 56),
	command_label = "  Command:",
	warning_prefix = "  ⚠️  WARNING: ",
	options = {
		"  [y] Allow once           - Execute this command",
		"  [s] Allow this session   - Auto-allow until restart",
		"  [a] Add to allow list    - Always allow this command",
		"  [n] Reject               - Cancel execution",
	},
	cancel_hint = "  Press key to choose | [q] or [Esc] to cancel",
}

--- Diff view help message
M.diff_help = {
	{ "Diff: ", "Normal" },
	{ "{path}", "Directory" },
	{ " | ", "Normal" },
	{ "y/<CR>", "Keyword" },
	{ " approve  ", "Normal" },
	{ "n/q/<Esc>", "Keyword" },
	{ " reject  ", "Normal" },
	{ "<Tab>", "Keyword" },
	{ " switch panes", "Normal" },
}


--- Review UI interface strings
M.review = {
	diff_header = {
		top = "╭─ %s %s %s ─────────────────────────────────────",
		path = "│ %s",
		op = "│ Operation: %s",
		status = "│ Status: %s",
		bottom = "╰────────────────────────────────────────────────────",
	},
	list_menu = {
		top = "╭─ Changes (%s) ──────────╮",
		items = {
			"│                              │",
			"│ j/k: navigate               │",
			"│ Enter: view diff            │",
			"│ a: approve  r: reject       │",
			"│ A: approve all              │",
			"│ q: close                    │",
		},
		bottom = "╰──────────────────────────────╯",
	},
	status = {
		applied = "Applied",
		approved = "Approved",
		pending = "Pending",
	},
	messages = {
		no_changes = "  No changes to review",
		no_changes_short = "No changes to review",
		applied_count = "Applied %d change(s)",
	},
}

return M
