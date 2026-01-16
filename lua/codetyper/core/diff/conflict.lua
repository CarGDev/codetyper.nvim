---@mod codetyper.agent.conflict Git conflict-style diff visualization
---@brief [[
--- Provides interactive conflict resolution for AI-generated code changes.
--- Uses git merge conflict markers (<<<<<<< / ======= / >>>>>>>) with
--- extmark highlighting for visual differentiation.
---
--- Keybindings in conflict buffers:
---   co = accept "ours" (keep original code)
---   ct = accept "theirs" (use AI suggestion)
---   cb = accept "both" (keep both versions)
---   cn = accept "none" (delete both versions)
---   [x = jump to previous conflict
---   ]x = jump to next conflict
---@brief ]]

local M = {}

local params = require("codetyper.params.agent.conflict")

--- Lazy load linter module
local function get_linter()
	return require("codetyper.features.agents.linter")
end

--- Configuration
local config = vim.deepcopy(params.config)

--- Namespace for conflict highlighting
local NAMESPACE = vim.api.nvim_create_namespace("codetyper_conflict")

--- Namespace for keybinding hints
local HINT_NAMESPACE = vim.api.nvim_create_namespace("codetyper_conflict_hints")

--- Highlight groups
local HL_GROUPS = params.hl_groups

--- Conflict markers
local MARKERS = params.markers

--- Track buffers with active conflicts
local conflict_buffers = {}

--- Run linter validation after accepting code changes
---@param bufnr number Buffer number
---@param start_line number Start line of changed region
---@param end_line number End line of changed region
---@param accepted_type string Type of acceptance ("theirs", "both")
local function validate_after_accept(bufnr, start_line, end_line, accepted_type)
	if not config.lint_after_accept then
		return
	end

	-- Only validate when accepting AI suggestions
	if accepted_type ~= "theirs" and accepted_type ~= "both" then
		return
	end

	local linter = get_linter()

	-- Validate the changed region
	linter.validate_after_injection(bufnr, start_line, end_line, function(result)
		if not result then
			return
		end

		-- If errors found and auto-fix is enabled, queue fix automatically
		if result.has_errors and config.auto_fix_lint_errors then
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "info",
					message = "Auto-queuing fix for lint errors...",
				})
			end)
			linter.request_ai_fix(bufnr, result)
		end
	end)
end

--- Configure conflict behavior
---@param opts table Configuration options
function M.configure(opts)
	for k, v in pairs(opts) do
		if config[k] ~= nil then
			config[k] = v
		end
	end
end

--- Get current configuration
---@return table
function M.get_config()
	return vim.deepcopy(config)
end

--- Auto-show menu for next conflict if enabled and conflicts remain
---@param bufnr number Buffer number
local function auto_show_next_conflict_menu(bufnr)
	if not config.auto_show_next_menu then
		return
	end

	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		local conflicts = M.detect_conflicts(bufnr)
		if #conflicts > 0 then
			-- Jump to first remaining conflict and show menu
			local conflict = conflicts[1]
			local win = vim.api.nvim_get_current_win()
			if vim.api.nvim_win_get_buf(win) == bufnr then
				vim.api.nvim_win_set_cursor(win, { conflict.start_line, 0 })
				vim.cmd("normal! zz")
				M.show_floating_menu(bufnr)
			end
		end
	end)
end

--- Setup highlight groups
local function setup_highlights()
	-- Current (original) code - green tint
	vim.api.nvim_set_hl(0, HL_GROUPS.current, {
		bg = "#2d4a3e",
		default = true,
	})
	vim.api.nvim_set_hl(0, HL_GROUPS.current_label, {
		fg = "#98c379",
		bg = "#2d4a3e",
		bold = true,
		default = true,
	})

	-- Incoming (AI suggestion) code - blue tint
	vim.api.nvim_set_hl(0, HL_GROUPS.incoming, {
		bg = "#2d3a4a",
		default = true,
	})
	vim.api.nvim_set_hl(0, HL_GROUPS.incoming_label, {
		fg = "#61afef",
		bg = "#2d3a4a",
		bold = true,
		default = true,
	})

	-- Separator line
	vim.api.nvim_set_hl(0, HL_GROUPS.separator, {
		fg = "#5c6370",
		bg = "#3e4451",
		bold = true,
		default = true,
	})

	-- Keybinding hints
	vim.api.nvim_set_hl(0, HL_GROUPS.hint, {
		fg = "#5c6370",
		italic = true,
		default = true,
	})
end

--- Parse a buffer and find all conflict regions
---@param bufnr number Buffer number
---@return table[] conflicts List of conflict positions
function M.detect_conflicts(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local conflicts = {}
	local current_conflict = nil

	for i, line in ipairs(lines) do
		if line:match("^<<<<<<<") then
			current_conflict = {
				start_line = i,
				current_start = i,
				current_end = nil,
				separator = nil,
				incoming_start = nil,
				incoming_end = nil,
				end_line = nil,
			}
		elseif line:match("^=======") and current_conflict then
			current_conflict.current_end = i - 1
			current_conflict.separator = i
			current_conflict.incoming_start = i + 1
		elseif line:match("^>>>>>>>") and current_conflict then
			current_conflict.incoming_end = i - 1
			current_conflict.end_line = i
			table.insert(conflicts, current_conflict)
			current_conflict = nil
		end
	end

	return conflicts
end

--- Highlight conflicts in buffer using extmarks
---@param bufnr number Buffer number
---@param conflicts table[] Conflict positions
function M.highlight_conflicts(bufnr, conflicts)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
	vim.api.nvim_buf_clear_namespace(bufnr, HINT_NAMESPACE, 0, -1)

	for _, conflict in ipairs(conflicts) do
		-- Highlight <<<<<<< CURRENT line
		vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, conflict.start_line - 1, 0, {
			end_row = conflict.start_line - 1,
			end_col = 0,
			line_hl_group = HL_GROUPS.current_label,
			priority = 100,
		})

		-- Highlight current (original) code section
		if conflict.current_start and conflict.current_end then
			for row = conflict.current_start, conflict.current_end do
				if row <= conflict.current_end then
					vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row - 1, 0, {
						end_row = row - 1,
						end_col = 0,
						line_hl_group = HL_GROUPS.current,
						priority = 90,
					})
				end
			end
		end

		-- Highlight ======= separator
		if conflict.separator then
			vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, conflict.separator - 1, 0, {
				end_row = conflict.separator - 1,
				end_col = 0,
				line_hl_group = HL_GROUPS.separator,
				priority = 100,
			})
		end

		-- Highlight incoming (AI suggestion) code section
		if conflict.incoming_start and conflict.incoming_end then
			for row = conflict.incoming_start, conflict.incoming_end do
				if row <= conflict.incoming_end then
					vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row - 1, 0, {
						end_row = row - 1,
						end_col = 0,
						line_hl_group = HL_GROUPS.incoming,
						priority = 90,
					})
				end
			end
		end

		-- Highlight >>>>>>> INCOMING line
		if conflict.end_line then
			vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, conflict.end_line - 1, 0, {
				end_row = conflict.end_line - 1,
				end_col = 0,
				line_hl_group = HL_GROUPS.incoming_label,
				priority = 100,
			})
		end

		-- Add virtual text hint on the <<<<<<< line
		vim.api.nvim_buf_set_extmark(bufnr, HINT_NAMESPACE, conflict.start_line - 1, 0, {
			virt_text = {
				{ "  [co]=ours [ct]=theirs [cb]=both [cn]=none [x/]x=nav", HL_GROUPS.hint },
			},
			virt_text_pos = "eol",
			priority = 50,
		})
	end
end

--- Get the conflict at the current cursor position
---@param bufnr number Buffer number
---@param cursor_line number Current line (1-indexed)
---@return table|nil conflict The conflict at cursor, or nil
function M.get_conflict_at_cursor(bufnr, cursor_line)
	local conflicts = M.detect_conflicts(bufnr)

	for _, conflict in ipairs(conflicts) do
		if cursor_line >= conflict.start_line and cursor_line <= conflict.end_line then
			return conflict
		end
	end

	return nil
end

--- Accept "ours" - keep the original code
---@param bufnr number Buffer number
function M.accept_ours(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

	if not conflict then
		vim.notify("No conflict at cursor position", vim.log.levels.WARN)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Extract the "current" (original) lines
	local keep_lines = {}
	if conflict.current_start and conflict.current_end then
		for i = conflict.current_start + 1, conflict.current_end do
			table.insert(keep_lines, lines[i])
		end
	end

	-- Replace the entire conflict region with the kept lines
	vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, keep_lines)

	-- Re-process remaining conflicts
	M.process(bufnr)

	vim.notify("Accepted CURRENT (original) code", vim.log.levels.INFO)

	-- Auto-show menu for next conflict if any remain
	auto_show_next_conflict_menu(bufnr)
end

--- Accept "theirs" - use the AI suggestion
---@param bufnr number Buffer number
function M.accept_theirs(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

	if not conflict then
		vim.notify("No conflict at cursor position", vim.log.levels.WARN)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Extract the "incoming" (AI suggestion) lines
	local keep_lines = {}
	if conflict.incoming_start and conflict.incoming_end then
		for i = conflict.incoming_start, conflict.incoming_end do
			table.insert(keep_lines, lines[i])
		end
	end

	-- Track where the code will be inserted
	local insert_start = conflict.start_line
	local insert_end = insert_start + #keep_lines - 1

	-- Replace the entire conflict region with the kept lines
	vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, keep_lines)

	-- Re-process remaining conflicts
	M.process(bufnr)

	vim.notify("Accepted INCOMING (AI suggestion) code", vim.log.levels.INFO)

	-- Run linter validation on the accepted code
	validate_after_accept(bufnr, insert_start, insert_end, "theirs")

	-- Auto-show menu for next conflict if any remain
	auto_show_next_conflict_menu(bufnr)
end

--- Accept "both" - keep both versions
---@param bufnr number Buffer number
function M.accept_both(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

	if not conflict then
		vim.notify("No conflict at cursor position", vim.log.levels.WARN)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Extract both "current" and "incoming" lines
	local keep_lines = {}

	-- Add current lines
	if conflict.current_start and conflict.current_end then
		for i = conflict.current_start + 1, conflict.current_end do
			table.insert(keep_lines, lines[i])
		end
	end

	-- Add incoming lines
	if conflict.incoming_start and conflict.incoming_end then
		for i = conflict.incoming_start, conflict.incoming_end do
			table.insert(keep_lines, lines[i])
		end
	end

	-- Track where the code will be inserted
	local insert_start = conflict.start_line
	local insert_end = insert_start + #keep_lines - 1

	-- Replace the entire conflict region with the kept lines
	vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, keep_lines)

	-- Re-process remaining conflicts
	M.process(bufnr)

	vim.notify("Accepted BOTH (current + incoming) code", vim.log.levels.INFO)

	-- Run linter validation on the accepted code
	validate_after_accept(bufnr, insert_start, insert_end, "both")

	-- Auto-show menu for next conflict if any remain
	auto_show_next_conflict_menu(bufnr)
end

--- Accept "none" - delete both versions
---@param bufnr number Buffer number
function M.accept_none(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

	if not conflict then
		vim.notify("No conflict at cursor position", vim.log.levels.WARN)
		return
	end

	-- Replace the entire conflict region with nothing
	vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, {})

	-- Re-process remaining conflicts
	M.process(bufnr)

	vim.notify("Deleted conflict (accepted NONE)", vim.log.levels.INFO)

	-- Auto-show menu for next conflict if any remain
	auto_show_next_conflict_menu(bufnr)
end

--- Navigate to the next conflict
---@param bufnr number Buffer number
---@return boolean found Whether a conflict was found
function M.goto_next(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]
	local conflicts = M.detect_conflicts(bufnr)

	for _, conflict in ipairs(conflicts) do
		if conflict.start_line > cursor_line then
			vim.api.nvim_win_set_cursor(0, { conflict.start_line, 0 })
			vim.cmd("normal! zz")
			return true
		end
	end

	-- Wrap around to first conflict
	if #conflicts > 0 then
		vim.api.nvim_win_set_cursor(0, { conflicts[1].start_line, 0 })
		vim.cmd("normal! zz")
		vim.notify("Wrapped to first conflict", vim.log.levels.INFO)
		return true
	end

	vim.notify("No more conflicts", vim.log.levels.INFO)
	return false
end

--- Navigate to the previous conflict
---@param bufnr number Buffer number
---@return boolean found Whether a conflict was found
function M.goto_prev(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]
	local conflicts = M.detect_conflicts(bufnr)

	for i = #conflicts, 1, -1 do
		local conflict = conflicts[i]
		if conflict.start_line < cursor_line then
			vim.api.nvim_win_set_cursor(0, { conflict.start_line, 0 })
			vim.cmd("normal! zz")
			return true
		end
	end

	-- Wrap around to last conflict
	if #conflicts > 0 then
		vim.api.nvim_win_set_cursor(0, { conflicts[#conflicts].start_line, 0 })
		vim.cmd("normal! zz")
		vim.notify("Wrapped to last conflict", vim.log.levels.INFO)
		return true
	end

	vim.notify("No more conflicts", vim.log.levels.INFO)
	return false
end

--- Show conflict resolution menu modal
---@param bufnr number Buffer number
function M.show_menu(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

	if not conflict then
		vim.notify("No conflict at cursor position", vim.log.levels.WARN)
		return
	end

	-- Get preview of both versions
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local current_preview = ""
	if conflict.current_start and conflict.current_end then
		local current_lines = {}
		for i = conflict.current_start + 1, math.min(conflict.current_end, conflict.current_start + 3) do
			if lines[i] then
				table.insert(current_lines, "  " .. lines[i]:sub(1, 50))
			end
		end
		if conflict.current_end - conflict.current_start > 3 then
			table.insert(current_lines, "  ...")
		end
		current_preview = table.concat(current_lines, "\n")
	end

	local incoming_preview = ""
	if conflict.incoming_start and conflict.incoming_end then
		local incoming_lines = {}
		for i = conflict.incoming_start, math.min(conflict.incoming_end, conflict.incoming_start + 2) do
			if lines[i] then
				table.insert(incoming_lines, "  " .. lines[i]:sub(1, 50))
			end
		end
		if conflict.incoming_end - conflict.incoming_start > 3 then
			table.insert(incoming_lines, "  ...")
		end
		incoming_preview = table.concat(incoming_lines, "\n")
	end

	-- Count lines in each section
	local current_count = conflict.current_end and conflict.current_start
		and (conflict.current_end - conflict.current_start) or 0
	local incoming_count = conflict.incoming_end and conflict.incoming_start
		and (conflict.incoming_end - conflict.incoming_start + 1) or 0

	-- Build menu options
	local options = {
		{
			label = string.format("Accept CURRENT (original) - %d lines", current_count),
			key = "co",
			action = function() M.accept_ours(bufnr) end,
			preview = current_preview,
		},
		{
			label = string.format("Accept INCOMING (AI suggestion) - %d lines", incoming_count),
			key = "ct",
			action = function() M.accept_theirs(bufnr) end,
			preview = incoming_preview,
		},
		{
			label = string.format("Accept BOTH versions - %d lines total", current_count + incoming_count),
			key = "cb",
			action = function() M.accept_both(bufnr) end,
		},
		{
			label = "Delete conflict (accept NONE)",
			key = "cn",
			action = function() M.accept_none(bufnr) end,
		},
		{
			label = "─────────────────────────",
			key = "",
			action = nil,
			separator = true,
		},
		{
			label = "Next conflict",
			key = "]x",
			action = function() M.goto_next(bufnr) end,
		},
		{
			label = "Previous conflict",
			key = "[x",
			action = function() M.goto_prev(bufnr) end,
		},
	}

	-- Build display labels
	local labels = {}
	for _, opt in ipairs(options) do
		if opt.separator then
			table.insert(labels, opt.label)
		else
			table.insert(labels, string.format("[%s] %s", opt.key, opt.label))
		end
	end

	-- Show menu using vim.ui.select
	vim.ui.select(labels, {
		prompt = "Resolve Conflict:",
		format_item = function(item)
			return item
		end,
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		local selected = options[idx]
		if selected and selected.action then
			selected.action()
		end
	end)
end

--- Show floating window menu for conflict resolution
---@param bufnr number Buffer number
function M.show_floating_menu(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

	if not conflict then
		vim.notify("No conflict at cursor position", vim.log.levels.WARN)
		return
	end

	-- Get lines for preview
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Count lines
	local current_count = conflict.current_end and conflict.current_start
		and (conflict.current_end - conflict.current_start) or 0
	local incoming_count = conflict.incoming_end and conflict.incoming_start
		and (conflict.incoming_end - conflict.incoming_start + 1) or 0

	-- Build menu content
	local menu_lines = {
		"╭─────────────────────────────────────────╮",
		"│       Resolve Conflict                  │",
		"├─────────────────────────────────────────┤",
		string.format("│ [co] Accept CURRENT (original) %3d lines│", current_count),
		string.format("│ [ct] Accept INCOMING (AI)      %3d lines│", incoming_count),
		string.format("│ [cb] Accept BOTH               %3d lines│", current_count + incoming_count),
		"│ [cn] Delete conflict (NONE)             │",
		"├─────────────────────────────────────────┤",
		"│ []x] Next conflict                      │",
		"│ [[x] Previous conflict                  │",
		"│ [q]  Close menu                         │",
		"╰─────────────────────────────────────────╯",
	}

	-- Create floating window
	local width = 43
	local height = #menu_lines

	local float_opts = {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = true,
	}

	-- Create buffer for menu
	local menu_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(menu_bufnr, 0, -1, false, menu_lines)
	vim.bo[menu_bufnr].modifiable = false
	vim.bo[menu_bufnr].bufhidden = "wipe"

	-- Open floating window
	local win = vim.api.nvim_open_win(menu_bufnr, true, float_opts)

	-- Set highlights
	vim.api.nvim_set_hl(0, "CoderConflictMenuBorder", { fg = "#61afef", default = true })
	vim.api.nvim_set_hl(0, "CoderConflictMenuTitle", { fg = "#e5c07b", bold = true, default = true })
	vim.api.nvim_set_hl(0, "CoderConflictMenuKey", { fg = "#98c379", bold = true, default = true })

	vim.wo[win].winhl = "Normal:Normal,FloatBorder:CoderConflictMenuBorder"

	-- Add syntax highlighting to menu buffer
	vim.api.nvim_buf_add_highlight(menu_bufnr, -1, "CoderConflictMenuTitle", 1, 0, -1)
	for i = 3, 9 do
		-- Highlight the key in brackets
		local line = menu_lines[i + 1]
		if line then
			local start_col = line:find("%[")
			local end_col = line:find("%]")
			if start_col and end_col then
				vim.api.nvim_buf_add_highlight(menu_bufnr, -1, "CoderConflictMenuKey", i, start_col - 1, end_col)
			end
		end
	end

	-- Setup keymaps for the menu
	local close_menu = function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	-- Use nowait to prevent delay from built-in 'c' command
	local menu_opts = { buffer = menu_bufnr, silent = true, noremap = true, nowait = true }

	vim.keymap.set("n", "q", close_menu, menu_opts)
	vim.keymap.set("n", "<Esc>", close_menu, menu_opts)

	vim.keymap.set("n", "co", function()
		close_menu()
		M.accept_ours(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "ct", function()
		close_menu()
		M.accept_theirs(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "cb", function()
		close_menu()
		M.accept_both(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "cn", function()
		close_menu()
		M.accept_none(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "]x", function()
		close_menu()
		M.goto_next(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "[x", function()
		close_menu()
		M.goto_prev(bufnr)
	end, menu_opts)

	-- Also support number keys for quick selection
	vim.keymap.set("n", "1", function()
		close_menu()
		M.accept_ours(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "2", function()
		close_menu()
		M.accept_theirs(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "3", function()
		close_menu()
		M.accept_both(bufnr)
	end, menu_opts)

	vim.keymap.set("n", "4", function()
		close_menu()
		M.accept_none(bufnr)
	end, menu_opts)

	-- Close on focus lost
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = menu_bufnr,
		once = true,
		callback = close_menu,
	})
end

--- Setup keybindings for conflict resolution in a buffer
---@param bufnr number Buffer number
function M.setup_keymaps(bufnr)
	-- Use nowait to prevent delay from built-in 'c' command
	local opts = { buffer = bufnr, silent = true, noremap = true, nowait = true }

	-- Accept ours (original)
	vim.keymap.set("n", "co", function()
		M.accept_ours(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Accept CURRENT (original) code" }))

	-- Accept theirs (AI suggestion)
	vim.keymap.set("n", "ct", function()
		M.accept_theirs(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Accept INCOMING (AI suggestion) code" }))

	-- Accept both
	vim.keymap.set("n", "cb", function()
		M.accept_both(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Accept BOTH versions" }))

	-- Accept none
	vim.keymap.set("n", "cn", function()
		M.accept_none(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Delete conflict (accept NONE)" }))

	-- Navigate to next conflict
	vim.keymap.set("n", "]x", function()
		M.goto_next(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Go to next conflict" }))

	-- Navigate to previous conflict
	vim.keymap.set("n", "[x", function()
		M.goto_prev(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Go to previous conflict" }))

	-- Show menu modal
	vim.keymap.set("n", "cm", function()
		M.show_floating_menu(bufnr)
	end, vim.tbl_extend("force", opts, { desc = "Show conflict resolution menu" }))

	-- Also map <CR> to show menu when on conflict
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(0)
		if M.get_conflict_at_cursor(bufnr, cursor[1]) then
			M.show_floating_menu(bufnr)
		else
			-- Default <CR> behavior
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
		end
	end, vim.tbl_extend("force", opts, { desc = "Show conflict menu or default action" }))

	-- Mark buffer as having conflict keymaps
	conflict_buffers[bufnr] = {
		keymaps_set = true,
	}
end

--- Remove keybindings from a buffer
---@param bufnr number Buffer number
function M.remove_keymaps(bufnr)
	if not conflict_buffers[bufnr] then
		return
	end

	pcall(vim.keymap.del, "n", "co", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "ct", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "cb", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "cn", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "cm", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "]x", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "[x", { buffer = bufnr })
	pcall(vim.keymap.del, "n", "<CR>", { buffer = bufnr })

	conflict_buffers[bufnr] = nil
end

--- Insert conflict markers for a code change
---@param bufnr number Buffer number
---@param start_line number Start line (1-indexed)
---@param end_line number End line (1-indexed)
---@param new_lines string[] New lines to insert as "incoming"
---@param label? string Optional label for the incoming section
function M.insert_conflict(bufnr, start_line, end_line, new_lines, label)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Clamp to valid range
	local line_count = #lines
	start_line = math.max(1, math.min(start_line, line_count + 1))
	end_line = math.max(start_line, math.min(end_line, line_count))

	-- Extract current lines
	local current_lines = {}
	for i = start_line, end_line do
		if lines[i] then
			table.insert(current_lines, lines[i])
		end
	end

	-- Build conflict block
	local conflict_block = {}
	table.insert(conflict_block, MARKERS.current_start)
	for _, line in ipairs(current_lines) do
		table.insert(conflict_block, line)
	end
	table.insert(conflict_block, MARKERS.separator)
	for _, line in ipairs(new_lines) do
		table.insert(conflict_block, line)
	end
	table.insert(conflict_block, label and (">>>>>>> " .. label) or MARKERS.incoming_end)

	-- Replace the range with conflict block
	vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, conflict_block)
end

--- Process buffer and auto-show menu for first conflict
--- Call this after inserting conflict(s) to set up highlights and show menu
---@param bufnr number Buffer number
function M.process_and_show_menu(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Process to set up highlights and keymaps
	local conflict_count = M.process(bufnr)

	-- Auto-show menu if enabled and conflicts exist
	if config.auto_show_menu and conflict_count > 0 then
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			-- Find window showing this buffer and focus it
			local win = nil
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_get_buf(w) == bufnr then
					win = w
					break
				end
			end

			if win then
				vim.api.nvim_set_current_win(win)
				-- Jump to first conflict
				local conflicts = M.detect_conflicts(bufnr)
				if #conflicts > 0 then
					vim.api.nvim_win_set_cursor(win, { conflicts[1].start_line, 0 })
					vim.cmd("normal! zz")
					-- Show the menu
					M.show_floating_menu(bufnr)
				end
			end
		end)
	end
end

--- Process a buffer for conflicts - detect, highlight, and setup keymaps
---@param bufnr number Buffer number
---@return number conflict_count Number of conflicts found
function M.process(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return 0
	end

	-- Setup highlights if not done
	setup_highlights()

	-- Detect conflicts
	local conflicts = M.detect_conflicts(bufnr)

	if #conflicts > 0 then
		-- Highlight conflicts
		M.highlight_conflicts(bufnr, conflicts)

		-- Setup keymaps if not already done
		if not conflict_buffers[bufnr] then
			M.setup_keymaps(bufnr)
		end

		-- Log
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.info(string.format("Found %d conflict(s) - use co/ct/cb/cn to resolve, [x/]x to navigate", #conflicts))
		end)
	else
		-- No conflicts - clean up
		vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
		vim.api.nvim_buf_clear_namespace(bufnr, HINT_NAMESPACE, 0, -1)
		M.remove_keymaps(bufnr)
	end

	return #conflicts
end

--- Check if a buffer has conflicts
---@param bufnr number Buffer number
---@return boolean
function M.has_conflicts(bufnr)
	local conflicts = M.detect_conflicts(bufnr)
	return #conflicts > 0
end

--- Get conflict count for a buffer
---@param bufnr number Buffer number
---@return number
function M.count_conflicts(bufnr)
	local conflicts = M.detect_conflicts(bufnr)
	return #conflicts
end

--- Clear all conflicts from a buffer (remove markers but keep current code)
---@param bufnr number Buffer number
---@param keep "ours"|"theirs"|"both"|"none" Which version to keep
function M.resolve_all(bufnr, keep)
	local conflicts = M.detect_conflicts(bufnr)

	-- Process in reverse order to maintain line numbers
	for i = #conflicts, 1, -1 do
		-- Move cursor to conflict
		vim.api.nvim_win_set_cursor(0, { conflicts[i].start_line, 0 })

		-- Accept based on preference
		if keep == "ours" then
			M.accept_ours(bufnr)
		elseif keep == "theirs" then
			M.accept_theirs(bufnr)
		elseif keep == "both" then
			M.accept_both(bufnr)
		else
			M.accept_none(bufnr)
		end
	end
end

--- Add a buffer to conflict tracking (for auto-follow)
---@param bufnr number Buffer number
function M.add_tracked_buffer(bufnr)
	if not conflict_buffers[bufnr] then
		conflict_buffers[bufnr] = {}
	end
end

--- Get all tracked buffers with conflicts
---@return number[] buffers List of buffer numbers
function M.get_tracked_buffers()
	local buffers = {}
	for bufnr, _ in pairs(conflict_buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) and M.has_conflicts(bufnr) then
			table.insert(buffers, bufnr)
		end
	end
	return buffers
end

--- Clear tracking for a buffer
---@param bufnr number Buffer number
function M.clear_buffer(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
	vim.api.nvim_buf_clear_namespace(bufnr, HINT_NAMESPACE, 0, -1)
	M.remove_keymaps(bufnr)
	conflict_buffers[bufnr] = nil
end

--- Initialize the conflict module
function M.setup()
	setup_highlights()

	-- Auto-clean up when buffers are deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		group = vim.api.nvim_create_augroup("CoderConflict", { clear = true }),
		callback = function(ev)
			conflict_buffers[ev.buf] = nil
		end,
	})
end

return M
