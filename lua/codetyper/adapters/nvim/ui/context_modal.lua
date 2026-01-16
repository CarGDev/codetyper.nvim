---@mod codetyper.agent.context_modal Modal for additional context input
---@brief [[
--- Opens a floating window for user to provide additional context
--- when the LLM requests more information.
---@brief ]]

local M = {}

---@class ContextModalState
---@field buf number|nil Buffer number
---@field win number|nil Window number
---@field original_event table|nil Original prompt event
---@field callback function|nil Callback with additional context
---@field llm_response string|nil LLM's response asking for context

local state = {
	buf = nil,
	win = nil,
	original_event = nil,
	callback = nil,
	llm_response = nil,
	attached_files = nil,
}

--- Close the context modal
function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	state.win = nil
	state.buf = nil
	state.original_event = nil
	state.callback = nil
	state.llm_response = nil
end

--- Submit the additional context
local function submit()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
	local additional_context = table.concat(lines, "\n")

	-- Trim whitespace
	additional_context = additional_context:match("^%s*(.-)%s*$") or additional_context

	if additional_context == "" then
		M.close()
		return
	end

	local original_event = state.original_event
	local callback = state.callback

	M.close()

	if callback and original_event then
		-- Pass attached_files as third optional parameter
		callback(original_event, additional_context, state.attached_files)
	end
end


--- Parse requested file paths from LLM response and resolve to full paths
local function parse_requested_files(response)
	if not response or response == "" then
		return {}
	end

	local cwd = vim.fn.getcwd()
	local candidates = {}
	local seen = {}

	for path in response:gmatch("`([%w%._%-%/]+%.[%w_]+)`") do
		if not seen[path] then
			table.insert(candidates, path)
			seen[path] = true
		end
	end
	for path in response:gmatch("([%w%._%-%/]+%.[%w_]+)") do
		if not seen[path] then
			table.insert(candidates, path)
			seen[path] = true
		end
	end

	-- Resolve to full paths using cwd and glob
	local resolved = {}
	for _, p in ipairs(candidates) do
		local full = nil
		if p:sub(1,1) == "/" and vim.fn.filereadable(p) == 1 then
			full = p
		else
			local try1 = cwd .. "/" .. p
			if vim.fn.filereadable(try1) == 1 then
				full = try1
			else
				local tail = p:match("[^/]+$") or p
				local matches = vim.fn.globpath(cwd, "**/" .. tail, false, true)
				if matches and #matches > 0 then
					full = matches[1]
				end
			end
		end
		if full and vim.fn.filereadable(full) == 1 then
			table.insert(resolved, full)
		end
	end
	return resolved
end


--- Attach parsed files into the modal buffer and remember them for submission
local function attach_requested_files()
	if not state.llm_response or state.llm_response == "" then
		return
	end
	local files = parse_requested_files(state.llm_response)
	if #files == 0 then
		local ui_prompts = require("codetyper.prompts.agent.modal").ui
		vim.api.nvim_buf_set_lines(state.buf, vim.api.nvim_buf_line_count(state.buf), -1, false, ui_prompts.files_header)
		return
	end

	state.attached_files = state.attached_files or {}

	for _, full in ipairs(files) do
		local ok, lines = pcall(vim.fn.readfile, full)
		if ok and lines and #lines > 0 then
			table.insert(state.attached_files, { path = vim.fn.fnamemodify(full, ":~:." ) , full_path = full, content = table.concat(lines, "\n") })
			local insert_at = vim.api.nvim_buf_line_count(state.buf)
			vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, { "", "-- Attached: " .. full .. " --" })
			for i, l in ipairs(lines) do
				vim.api.nvim_buf_set_lines(state.buf, insert_at + 1 + i, insert_at + 1 + i, false, { l })
			end
		else
			local insert_at = vim.api.nvim_buf_line_count(state.buf)
			vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, { "", "-- Failed to read: " .. full .. " --" })
		end
	end
	-- Move cursor to end and enter insert mode
	vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
	vim.cmd("startinsert")
end

--- Open the context modal
---@param original_event table Original prompt event
---@param llm_response string LLM's response asking for context
---@param callback function(event: table, additional_context: string, attached_files?: table)
---@param suggested_commands table[]|nil Optional list of {label,cmd} suggested shell commands
function M.open(original_event, llm_response, callback, suggested_commands)
	-- Close any existing modal
	M.close()

	state.original_event = original_event
	state.llm_response = llm_response
	state.callback = callback

	-- Calculate window size
	local width = math.min(80, vim.o.columns - 10)
	local height = 10

	-- Create buffer
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].buftype = "nofile"
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "markdown"

	-- Create window
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Additional Context Needed ",
		title_pos = "center",
	})

	-- Set window options
	vim.wo[state.win].wrap = true
	vim.wo[state.win].cursorline = true

	local ui_prompts = require("codetyper.prompts.agent.modal").ui

	-- Add header showing what the LLM said
	local header_lines = {
		ui_prompts.llm_response_header,
	}

	-- Truncate LLM response for display
	local response_preview = llm_response or ""
	if #response_preview > 200 then
		response_preview = response_preview:sub(1, 200) .. "..."
	end
	for line in response_preview:gmatch("[^\n]+") do
		table.insert(header_lines, "-- " .. line)
	end

	-- If suggested commands were provided, show them in the header
	if suggested_commands and #suggested_commands > 0 then
		table.insert(header_lines, "")
		table.insert(header_lines, ui_prompts.suggested_commands_header)
		for i, s in ipairs(suggested_commands) do
			local label = s.label or s.cmd
			table.insert(header_lines, string.format("[%d] %s: %s", i, label, s.cmd))
		end
		table.insert(header_lines, ui_prompts.commands_hint)
	end

	table.insert(header_lines, "")
	table.insert(header_lines, ui_prompts.input_header)
	table.insert(header_lines, "")

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, header_lines)

	-- Move cursor to the end
	vim.api.nvim_win_set_cursor(state.win, { #header_lines, 0 })

	-- Set up keymaps
	local opts = { buffer = state.buf, noremap = true, silent = true }

	-- Submit with Ctrl+Enter or <leader>s
	vim.keymap.set("n", "<C-CR>", submit, opts)
	vim.keymap.set("i", "<C-CR>", submit, opts)
	vim.keymap.set("n", "<leader>s", submit, opts)
	vim.keymap.set("n", "<CR><CR>", submit, opts)

	-- Attach parsed files (from LLM response)
	vim.keymap.set("n", "a", function()
		attach_requested_files()
	end, opts)

	-- Confirm and submit with 'c' (convenient when doing question round)
	vim.keymap.set("n", "c", submit, opts)

	-- Quick run of project inspection from modal with <leader>r / <C-r> in insert mode
	vim.keymap.set("n", "<leader>r", run_project_inspect, opts)
	vim.keymap.set("i", "<C-r>", function()
		vim.schedule(run_project_inspect)
	end, { buffer = state.buf, noremap = true, silent = true })

	-- If suggested commands provided, create per-command keymaps <leader>1..n to run them
	state.suggested_commands = suggested_commands
	if suggested_commands and #suggested_commands > 0 then
		for i, s in ipairs(suggested_commands) do
			local key = "<leader>" .. tostring(i)
			vim.keymap.set("n", key, function()
				-- run this single command and append output
				if not s or not s.cmd then
					return
				end
				local ok, out = pcall(vim.fn.systemlist, s.cmd)
				local insert_at = vim.api.nvim_buf_line_count(state.buf)
				vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, { "", "-- Output: " .. s.cmd .. " --" })
				if ok and out and #out > 0 then
					for j, line in ipairs(out) do
						vim.api.nvim_buf_set_lines(state.buf, insert_at + j, insert_at + j, false, { line })
					end
				else
					vim.api.nvim_buf_set_lines(state.buf, insert_at + 1, insert_at + 1, false, { "(no output or command failed)" })
				end
				vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
				vim.cmd("startinsert")
			end, opts)
		end
		-- Also map <leader>0 to run all suggested commands
		vim.keymap.set("n", "<leader>0", function()
			for _, s in ipairs(suggested_commands) do
				pcall(function()
					local ok, out = pcall(vim.fn.systemlist, s.cmd)
					local insert_at = vim.api.nvim_buf_line_count(state.buf)
					vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, { "", "-- Output: " .. s.cmd .. " --" })
					if ok and out and #out > 0 then
						for j, line in ipairs(out) do
							vim.api.nvim_buf_set_lines(state.buf, insert_at + j, insert_at + j, false, { line })
						end
					else
						vim.api.nvim_buf_set_lines(state.buf, insert_at + 1, insert_at + 1, false, { "(no output or command failed)" })
					end
				end)
			end
			vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
			vim.cmd("startinsert")
		end, opts)
	end

	-- Close with Esc or q
	vim.keymap.set("n", "<Esc>", M.close, opts)
	vim.keymap.set("n", "q", M.close, opts)

	-- Start in insert mode
	vim.cmd("startinsert")

	-- Log
	pcall(function()
		local logs = require("codetyper.adapters.nvim.ui.logs")
		logs.add({
			type = "info",
			message = "Context modal opened - waiting for user input",
		})
	end)
end

--- Run a small set of safe project inspection commands and insert outputs into the modal buffer
local function run_project_inspect()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local cmds = {
		{ label = "List files (ls -la)", cmd = "ls -la" },
		{ label = "Git status (git status --porcelain)", cmd = "git status --porcelain" },
		{ label = "Git top (git rev-parse --show-toplevel)", cmd = "git rev-parse --show-toplevel" },
		{ label = "Show repo files (git ls-files)", cmd = "git ls-files" },
	}

	local ui_prompts = require("codetyper.prompts.agent.modal").ui
	local insert_pos = vim.api.nvim_buf_line_count(state.buf)
	vim.api.nvim_buf_set_lines(state.buf, insert_pos, insert_pos, false, ui_prompts.project_inspect_header)

	for _, c in ipairs(cmds) do
		local ok, out = pcall(vim.fn.systemlist, c.cmd)
		if ok and out and #out > 0 then
			vim.api.nvim_buf_set_lines(state.buf, insert_pos + 2, insert_pos + 2, false, { "-- " .. c.label .. " --" })
			for i, line in ipairs(out) do
				vim.api.nvim_buf_set_lines(state.buf, insert_pos + 2 + i, insert_pos + 2 + i, false, { line })
			end
			insert_pos = vim.api.nvim_buf_line_count(state.buf)
		else
			vim.api.nvim_buf_set_lines(state.buf, insert_pos + 2, insert_pos + 2, false, { "-- " .. c.label .. " --", "(no output or command failed)" })
			insert_pos = vim.api.nvim_buf_line_count(state.buf)
		end
	end

	-- Move cursor to end
	vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
	vim.cmd("startinsert")
end

-- Provide a keybinding in the modal to run project inspection commands
pcall(function()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.keymap.set("n", "<leader>r", run_project_inspect, { buffer = state.buf, noremap = true, silent = true })
		vim.keymap.set("i", "<C-r>", function()
			vim.schedule(run_project_inspect)
		end, { buffer = state.buf, noremap = true, silent = true })
	end
end)

--- Check if modal is open
---@return boolean
function M.is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Setup autocmds for the context modal
function M.setup()
	local group = vim.api.nvim_create_augroup("CodetypeContextModal", { clear = true })

	-- Close context modal when exiting Neovim
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.close()
		end,
		desc = "Close context modal before exiting Neovim",
	})
end

return M
