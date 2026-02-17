local M = {}

--- Return editor dimensions (from UI, like 99 plugin)
---@return number width
---@return number height
local function get_ui_dimensions()
	local ui = vim.api.nvim_list_uis()[1]
	if ui then
		return ui.width, ui.height
	end
	return vim.o.columns, vim.o.lines
end

--- Centered floating window config for prompt (2/3 width, 1/3 height)
---@return table { width, height, row, col, border }
local function create_centered_window()
	local width, height = get_ui_dimensions()
	local win_width = math.floor(width * 2 / 3)
	local win_height = math.floor(height / 3)
	return {
		width = win_width,
		height = win_height,
		row = math.floor((height - win_height) / 2),
		col = math.floor((width - win_width) / 2),
		border = "rounded",
	}
end

--- Get visual selection text and range
---@return table|nil { text: string, start_line: number, end_line: number }
local function get_visual_selection()
	local mode = vim.api.nvim_get_mode().mode
	-- Check if in visual mode
	local is_visual = mode == "v" or mode == "V" or mode == "\22"
	if not is_visual then
		return nil
	end
	-- Get selection range BEFORE any mode changes
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	-- Check if marks are valid (might be 0 if not in visual mode)
	if start_line <= 0 or end_line <= 0 then
		return nil
	end
	-- Third argument must be a Vim dictionary; empty Lua table can be treated as list
	local opts = { type = mode }
	local selection = vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), opts)
	local text = type(selection) == "table" and table.concat(selection, "\n") or tostring(selection or "")
	return {
		text = text,
		start_line = start_line,
		end_line = end_line,
	}
end

--- Transform visual selection with custom prompt input
--- Opens input window for prompt, processes selection on confirm.
--- When nothing is selected (e.g. from Normal mode), only the prompt is requested.
function M.cmd_transform_selection()
	local logger = require("codetyper.support.logger")
	logger.func_entry("commands", "cmd_transform_selection", {})
	-- Get visual selection (returns table with text, start_line, end_line or nil)
	local selection_data = get_visual_selection()
	local selection_text = selection_data and selection_data.text or ""
	local has_selection = selection_text and #selection_text >= 4

	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.fn.expand("%:p")
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	line_count = math.max(1, line_count)

	-- Range for injection: selection, cursor line when no selection
	local start_line, end_line
	local is_cursor_insert = false
	if has_selection and selection_data then
		start_line = selection_data.start_line
		end_line = selection_data.end_line
		logger.info("commands", string.format("Visual selection: start=%d end=%d selected_text_lines=%d",
			start_line, end_line, #vim.split(selection_text, "\n", { plain = true })))
	else
		-- No selection: insert at current cursor line (not replace whole file)
		start_line = vim.fn.line(".")
		end_line = start_line
		is_cursor_insert = true
	end
	-- Clamp to valid 1-based range (avoid 0 or out-of-bounds)
	start_line = math.max(1, math.min(start_line, line_count))
	end_line = math.max(1, math.min(end_line, line_count))
	if end_line < start_line then
		end_line = start_line
	end

	-- Capture injection range so we know exactly where to apply the generated code later
	local injection_range = { start_line = start_line, end_line = end_line }
	local range_line_count = end_line - start_line + 1

	-- Open centered prompt window (pattern from 99: acwrite + BufWriteCmd to submit, BufLeave to keep focus)
	local prompt_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[prompt_buf].buftype = "acwrite"
	vim.bo[prompt_buf].bufhidden = "wipe"
	vim.bo[prompt_buf].filetype = "markdown"
	vim.bo[prompt_buf].swapfile = false
	vim.api.nvim_buf_set_name(prompt_buf, "codetyper-prompt")

	local win_opts = create_centered_window()
	local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
		relative = "editor",
		row = win_opts.row,
		col = win_opts.col,
		width = win_opts.width,
		height = win_opts.height,
		style = "minimal",
		border = win_opts.border,
		title = has_selection and " Enter prompt for selection " or " Enter prompt ",
		title_pos = "center",
	})
	vim.wo[prompt_win].wrap = true
	vim.api.nvim_set_current_win(prompt_win)

	local function close_prompt()
		if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
			vim.api.nvim_win_close(prompt_win, true)
		end
		if prompt_buf and vim.api.nvim_buf_is_valid(prompt_buf) then
			vim.api.nvim_buf_delete(prompt_buf, { force = true })
		end
		prompt_win = nil
		prompt_buf = nil
	end

	local submitted = false

	local function submit_prompt()
		if not prompt_buf or not vim.api.nvim_buf_is_valid(prompt_buf) then
			close_prompt()
			return
		end
		submitted = true
		local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
		local input = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
		close_prompt()
		if input == "" then
			logger.info("commands", "User cancelled prompt input")
			return
		end
		local content
		if has_selection then
			content = input .. "\n\nCode to replace (replace this code):\n" .. selection_text
		elseif is_cursor_insert then
			content = "Insert at line " .. start_line .. ":\n" .. input
		else
			content = input
		end
		-- Pass captured range so scheduler/patch know where to inject the generated code
		local prompt = {
			content = content,
			start_line = injection_range.start_line,
			end_line = injection_range.end_line,
			start_col = 1,
			end_col = 1,
			user_prompt = input,
			-- Explicit injection range (same as start_line/end_line) for downstream
			injection_range = injection_range,
			-- When there's a selection, force replace; when no selection, insert at cursor
			intent_override = has_selection and { action = "replace" } or (is_cursor_insert and { action = "insert" } or nil),
		}
		local autocmds = require("codetyper.adapters.nvim.autocmds")
		autocmds.process_single_prompt(bufnr, prompt, filepath, true)
	end

	local augroup = vim.api.nvim_create_augroup("CodetyperPrompt_" .. prompt_buf, { clear = true })

	-- Submit on :w (acwrite buffer triggers BufWriteCmd)
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		buffer = prompt_buf,
		callback = function()
			if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
				submitted = true
				submit_prompt()
			end
		end,
	})

	-- Keep focus in prompt window (prevent leaving to other buffers)
	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = prompt_buf,
		callback = function()
			if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
				vim.api.nvim_set_current_win(prompt_win)
			end
		end,
	})

	-- Clean up when window is closed (e.g. :q or close button)
	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		pattern = tostring(prompt_win),
		callback = function()
			if not submitted then
				logger.info("commands", "User cancelled prompt input")
			end
			close_prompt()
		end,
	})

	local map_opts = { buffer = prompt_buf, noremap = true, silent = true }
	-- Normal mode: Enter, :w, or Ctrl+Enter to submit
	vim.keymap.set("n", "<CR>", submit_prompt, map_opts)
	vim.keymap.set("n", "<C-CR>", submit_prompt, map_opts)
	vim.keymap.set("n", "<C-Enter>", submit_prompt, map_opts)
	vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", vim.tbl_extend("force", map_opts, { desc = "Submit prompt" }))
	-- Insert mode: Ctrl+Enter to submit
	vim.keymap.set("i", "<C-CR>", submit_prompt, map_opts)
	vim.keymap.set("i", "<C-Enter>", submit_prompt, map_opts)
	-- Close/cancel: Esc (in normal), q, or :q
	vim.keymap.set("n", "<Esc>", close_prompt, map_opts)
	vim.keymap.set("n", "q", close_prompt, map_opts)

	vim.cmd("startinsert")
end

return M
