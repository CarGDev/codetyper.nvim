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
		callback(original_event, additional_context)
	end
end

--- Open the context modal
---@param original_event table Original prompt event
---@param llm_response string LLM's response asking for context
---@param callback function(event: table, additional_context: string)
function M.open(original_event, llm_response, callback)
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

	-- Add header showing what the LLM said
	local header_lines = {
		"-- LLM Response: --",
	}

	-- Truncate LLM response for display
	local response_preview = llm_response or ""
	if #response_preview > 200 then
		response_preview = response_preview:sub(1, 200) .. "..."
	end
	for line in response_preview:gmatch("[^\n]+") do
		table.insert(header_lines, "-- " .. line)
	end

	table.insert(header_lines, "")
	table.insert(header_lines, "-- Enter additional context below (Ctrl-Enter to submit, Esc to cancel) --")
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

	-- Close with Esc or q
	vim.keymap.set("n", "<Esc>", M.close, opts)
	vim.keymap.set("n", "q", M.close, opts)

	-- Start in insert mode
	vim.cmd("startinsert")

	-- Log
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "info",
			message = "Context modal opened - waiting for user input",
		})
	end)
end

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
