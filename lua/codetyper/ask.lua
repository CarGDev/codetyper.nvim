---@mod codetyper.ask Ask window for Codetyper.nvim (similar to avante.nvim)

local M = {}

local utils = require("codetyper.utils")

---@class AskState
---@field input_buf number|nil Input buffer
---@field input_win number|nil Input window
---@field output_buf number|nil Output buffer
---@field output_win number|nil Output window
---@field is_open boolean Whether the ask panel is open
---@field history table Chat history
---@field referenced_files table Files referenced with @

---@type AskState
local state = {
	input_buf = nil,
	input_win = nil,
	output_buf = nil,
	output_win = nil,
	is_open = false,
	history = {},
	referenced_files = {},
	target_width = nil, -- Store the target width to maintain it
	agent_mode = false, -- Whether agent mode is enabled (can make file changes)
	log_listener_id = nil, -- Listener ID for LLM logs
	show_logs = true, -- Whether to show LLM logs in chat
}

--- Get the ask window configuration
---@return table Config
local function get_config()
	local ok, codetyper = pcall(require, "codetyper")
	if ok and codetyper.is_initialized() then
		return codetyper.get_config()
	end
	return {
		window = { width = 0.4, border = "rounded" },
	}
end

--- Create the output buffer (chat history)
---@return number Buffer number
local function create_output_buffer()
	local buf = vim.api.nvim_create_buf(false, true)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"

	-- Set initial content
	local header = {
		"╔═════════════════════════════════╗",
		"║       [ASK MODE] Q&A Chat       ║",
		"╠═════════════════════════════════╣",
		"║ Ask about code or concepts      ║",
		"║                                 ║",
		"║ @ → attach file                 ║",
		"║ C-Enter → send                  ║",
		"║ C-n → new chat                  ║",
		"║ C-f → add current file          ║",
		"║ L → toggle LLM logs             ║",
		"║ :CoderType → switch mode        ║",
		"║ q → close │ K/J → jump          ║",
		"╚═════════════════════════════════╝",
		"",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, header)

	return buf
end

--- Create the input buffer
---@return number Buffer number
local function create_input_buffer()
	local buf = vim.api.nvim_create_buf(false, true)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"

	-- Set placeholder text
	local placeholder = {
		"┌───────────────────────────────────┐",
		"│ 💬 Type your question here...     │",
		"│                                   │",
		"│ @ attach │ C-Enter send │ C-n new │",
		"└───────────────────────────────────┘",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, placeholder)

	return buf
end

--- Setup keymaps for the input buffer
---@param buf number Buffer number
local function setup_input_keymaps(buf)
	local opts = { buffer = buf, noremap = true, silent = true }

	-- Submit with Ctrl+Enter
	vim.keymap.set("i", "<C-CR>", function()
		M.submit()
	end, opts)

	vim.keymap.set("n", "<C-CR>", function()
		M.submit()
	end, opts)

	vim.keymap.set("n", "<CR>", function()
		M.submit()
	end, opts)

	-- Include current file context with Ctrl+F
	vim.keymap.set({ "n", "i" }, "<C-f>", function()
		M.include_file_context()
	end, opts)

	-- File picker with @
	vim.keymap.set("i", "@", function()
		M.show_file_picker()
	end, opts)

	-- Close with q in normal mode
	vim.keymap.set("n", "q", function()
		M.close()
	end, opts)

	-- Clear input with Ctrl+c
	vim.keymap.set("n", "<C-c>", function()
		M.clear_input()
	end, opts)

	-- New chat with Ctrl+n (clears everything)
	vim.keymap.set({ "n", "i" }, "<C-n>", function()
		M.new_chat()
	end, opts)

	-- Window navigation (works in both normal and insert mode)
	vim.keymap.set({ "n", "i" }, "<C-h>", function()
		vim.cmd("wincmd h")
	end, opts)

	vim.keymap.set({ "n", "i" }, "<C-j>", function()
		vim.cmd("wincmd j")
	end, opts)

	vim.keymap.set({ "n", "i" }, "<C-k>", function()
		vim.cmd("wincmd k")
	end, opts)

	vim.keymap.set({ "n", "i" }, "<C-l>", function()
		vim.cmd("wincmd l")
	end, opts)

	-- Jump to output window
	vim.keymap.set("n", "K", function()
		M.focus_output()
	end, opts)

	-- When entering insert mode, clear placeholder
	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = buf,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			if content:match("Type your question here") then
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
			end
		end,
	})
end

--- Setup keymaps for the output buffer
---@param buf number Buffer number
local function setup_output_keymaps(buf)
	local opts = { buffer = buf, noremap = true, silent = true }

	-- Close with q
	vim.keymap.set("n", "q", function()
		M.close()
	end, opts)

	-- Clear history with Ctrl+c
	vim.keymap.set("n", "<C-c>", function()
		M.clear_history()
	end, opts)

	-- New chat with Ctrl+n (clears everything)
	vim.keymap.set("n", "<C-n>", function()
		M.new_chat()
	end, opts)

	-- Copy last response with Y
	vim.keymap.set("n", "Y", function()
		M.copy_last_response()
	end, opts)

	-- Toggle LLM logs with L
	vim.keymap.set("n", "L", function()
		M.toggle_logs()
	end, opts)

	-- Jump to input with i or J
	vim.keymap.set("n", "i", function()
		M.focus_input()
	end, opts)

	vim.keymap.set("n", "J", function()
		M.focus_input()
	end, opts)

	-- Window navigation
	vim.keymap.set("n", "<C-h>", function()
		vim.cmd("wincmd h")
	end, opts)

	vim.keymap.set("n", "<C-j>", function()
		vim.cmd("wincmd j")
	end, opts)

	vim.keymap.set("n", "<C-k>", function()
		vim.cmd("wincmd k")
	end, opts)

	vim.keymap.set("n", "<C-l>", function()
		vim.cmd("wincmd l")
	end, opts)
end

--- Calculate window dimensions (always 1/4 of screen)
---@return table Dimensions
local function calculate_dimensions()
	-- Always use 1/4 of the screen width
	local width = math.floor(vim.o.columns * 0.25)

	return {
		width = math.max(width, 30), -- Minimum 30 columns
		total_height = vim.o.lines - 4,
		output_height = vim.o.lines - 14,
		input_height = 8,
	}
end

--- Autocmd group for maintaining width
local ask_augroup = nil

--- Setup autocmd to always maintain 1/4 window width
local function setup_width_autocmd()
	-- Clear previous autocmd group if exists
	if ask_augroup then
		pcall(vim.api.nvim_del_augroup_by_id, ask_augroup)
	end

	ask_augroup = vim.api.nvim_create_augroup("CodetypeAskWidth", { clear = true })

	-- Always maintain 1/4 width on any window event
	vim.api.nvim_create_autocmd({ "WinResized", "WinNew", "WinClosed", "VimResized" }, {
		group = ask_augroup,
		callback = function()
			if not state.is_open or not state.output_win then
				return
			end
			if not vim.api.nvim_win_is_valid(state.output_win) then
				return
			end

			vim.schedule(function()
				if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
					-- Always calculate 1/4 of current screen width
					local target_width = math.max(math.floor(vim.o.columns * 0.25), 30)
					state.target_width = target_width

					local current_width = vim.api.nvim_win_get_width(state.output_win)
					if current_width ~= target_width then
						pcall(vim.api.nvim_win_set_width, state.output_win, target_width)
					end
				end
			end)
		end,
		desc = "Maintain Ask panel at 1/4 window width",
	})
end

--- Append log entry to output buffer
---@param entry table Log entry from agent/logs
local function append_log_to_output(entry)
	if not state.show_logs then
		return
	end

	if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
		return
	end

	-- Skip clear events
	if entry.level == "clear" then
		return
	end

	-- Format the log entry with icons
	local icons = {
		info = "ℹ️",
		debug = "🔍",
		request = "📤",
		response = "📥",
		tool = "🔧",
		error = "❌",
		warning = "⚠️",
	}

	local icon = icons[entry.level] or "•"
	-- Sanitize message - replace newlines with spaces to prevent nvim_buf_set_lines error
	local sanitized_message = entry.message:gsub("\n", " "):gsub("\r", "")
	local formatted = string.format("[%s] %s %s", entry.timestamp, icon, sanitized_message)

	vim.schedule(function()
		if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
			return
		end

		vim.bo[state.output_buf].modifiable = true

		local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)

		-- Add a subtle log line
		table.insert(lines, "  " .. formatted)

		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, lines)
		vim.bo[state.output_buf].modifiable = false

		-- Scroll to bottom
		if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
			local line_count = vim.api.nvim_buf_line_count(state.output_buf)
			pcall(vim.api.nvim_win_set_cursor, state.output_win, { line_count, 0 })
		end
	end)
end

--- Setup log listener for LLM logs
local function setup_log_listener()
	-- Remove existing listener if any
	if state.log_listener_id then
		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.remove_listener(state.log_listener_id)
		end)
		state.log_listener_id = nil
	end

	-- Add new listener
	local ok, logs = pcall(require, "codetyper.agent.logs")
	if ok then
		state.log_listener_id = logs.add_listener(append_log_to_output)
	end
end

--- Remove log listener
local function remove_log_listener()
	if state.log_listener_id then
		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.remove_listener(state.log_listener_id)
		end)
		state.log_listener_id = nil
	end
end

--- Open the ask panel
function M.open()
	-- Use the is_open() function which validates window state
	if M.is_open() then
		M.focus_input()
		return
	end

	local dims = calculate_dimensions()

	-- Store the target width
	state.target_width = dims.width

	-- Create buffers if they don't exist
	if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
		state.output_buf = create_output_buffer()
		setup_output_keymaps(state.output_buf)
	end

	if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
		state.input_buf = create_input_buffer()
		setup_input_keymaps(state.input_buf)
	end

	-- Save current window to return to it later
	local current_win = vim.api.nvim_get_current_win()

	-- Create output window (top-left)
	vim.cmd("topleft vsplit")
	state.output_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.output_win, state.output_buf)
	vim.api.nvim_win_set_width(state.output_win, dims.width)

	-- Window options for output
	vim.wo[state.output_win].number = false
	vim.wo[state.output_win].relativenumber = false
	vim.wo[state.output_win].signcolumn = "no"
	vim.wo[state.output_win].wrap = true
	vim.wo[state.output_win].linebreak = true
	vim.wo[state.output_win].cursorline = false
	vim.wo[state.output_win].winfixwidth = true

	-- Create input window (bottom of the left panel)
	vim.cmd("belowright split")
	state.input_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
	vim.api.nvim_win_set_height(state.input_win, dims.input_height)

	-- Window options for input
	vim.wo[state.input_win].number = false
	vim.wo[state.input_win].relativenumber = false
	vim.wo[state.input_win].signcolumn = "no"
	vim.wo[state.input_win].wrap = true
	vim.wo[state.input_win].linebreak = true
	vim.wo[state.input_win].winfixheight = true
	vim.wo[state.input_win].winfixwidth = true

	state.is_open = true

	-- Setup log listener for LLM logs
	setup_log_listener()

	-- Setup autocmd to maintain width
	setup_width_autocmd()

	-- Setup autocmd to close both windows when one is closed
	local close_group = vim.api.nvim_create_augroup("CodetypeAskClose", { clear = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = close_group,
		callback = function(args)
			local closed_win = tonumber(args.match)
			-- Check if one of our windows was closed
			if closed_win == state.output_win or closed_win == state.input_win then
				-- Defer to avoid issues during window close
				vim.schedule(function()
					-- Close the other window if it's still open
					if closed_win == state.output_win then
						if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
							pcall(vim.api.nvim_win_close, state.input_win, true)
						end
					elseif closed_win == state.input_win then
						if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
							pcall(vim.api.nvim_win_close, state.output_win, true)
						end
					end

					-- Reset state
					state.input_win = nil
					state.output_win = nil
					state.is_open = false
					state.target_width = nil

					-- Remove log listener
					remove_log_listener()

					-- Clean up autocmd groups
					pcall(vim.api.nvim_del_augroup_by_id, close_group)
					if ask_augroup then
						pcall(vim.api.nvim_del_augroup_by_id, ask_augroup)
						ask_augroup = nil
					end
				end)
			end
		end,
		desc = "Close both Ask windows together",
	})

	-- Focus the input window and start insert mode
	vim.api.nvim_set_current_win(state.input_win)
	vim.cmd("startinsert")
end

--- Show file picker for @ mentions
function M.show_file_picker()
	-- Check if telescope is available
	local has_telescope, telescope = pcall(require, "telescope.builtin")

	if has_telescope then
		telescope.find_files({
			prompt_title = "Select file to reference (@)",
			attach_mappings = function(prompt_bufnr, map)
				local actions = require("telescope.actions")
				local action_state = require("telescope.actions.state")

				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						local filepath = selection.path or selection[1]
						local filename = vim.fn.fnamemodify(filepath, ":t")
						M.add_file_reference(filepath, filename)
					end
				end)
				return true
			end,
		})
	else
		-- Fallback: simple input
		vim.ui.input({ prompt = "Enter file path: " }, function(input)
			if input and input ~= "" then
				local filepath = vim.fn.fnamemodify(input, ":p")
				local filename = vim.fn.fnamemodify(filepath, ":t")
				M.add_file_reference(filepath, filename)
			end
		end)
	end
end

--- Add a file reference to the input
---@param filepath string Full path to the file
---@param filename string Display name
function M.add_file_reference(filepath, filename)
	-- Normalize filepath
	filepath = vim.fn.fnamemodify(filepath, ":p")

	-- Store the reference with full path
	state.referenced_files[filename] = filepath

	-- Read and validate file exists
	local content = utils.read_file(filepath)
	if not content then
		utils.notify("Warning: Could not read file: " .. filename, vim.log.levels.WARN)
	end

	-- Add to input buffer
	if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
		local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
		local text = table.concat(lines, "\n")

		-- Clear placeholder if present
		if text:match("Type your question here") then
			text = ""
		end

		-- Add file reference (with single @)
		local reference = "[📎 " .. filename .. "] "
		text = text .. reference

		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, vim.split(text, "\n"))

		-- Move cursor to end
		if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
			vim.api.nvim_set_current_win(state.input_win)
			local line_count = vim.api.nvim_buf_line_count(state.input_buf)
			local last_line = vim.api.nvim_buf_get_lines(state.input_buf, line_count - 1, line_count, false)[1] or ""
			vim.api.nvim_win_set_cursor(state.input_win, { line_count, #last_line })
			vim.cmd("startinsert!")
		end
	end

	utils.notify("Added file: " .. filename .. " (" .. (content and #content or 0) .. " bytes)")
end

--- Close the ask panel
function M.close()
	-- Remove the log listener
	remove_log_listener()

	-- Remove the width maintenance autocmd first
	if ask_augroup then
		pcall(vim.api.nvim_del_augroup_by_id, ask_augroup)
		ask_augroup = nil
	end

	-- Find a window to focus after closing (not the ask windows)
	local target_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if win ~= state.input_win and win ~= state.output_win then
			local buftype = vim.bo[buf].buftype
			if buftype == "" or buftype == "acwrite" then
				target_win = win
				break
			end
		end
	end

	-- Close input window
	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		pcall(vim.api.nvim_win_close, state.input_win, true)
	end

	-- Close output window
	if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
		pcall(vim.api.nvim_win_close, state.output_win, true)
	end

	-- Reset state
	state.input_win = nil
	state.output_win = nil
	state.is_open = false
	state.target_width = nil

	-- Focus the target window if found, otherwise focus first available
	if target_win and vim.api.nvim_win_is_valid(target_win) then
		pcall(vim.api.nvim_set_current_win, target_win)
	else
		-- If no valid window, make sure we're not left with empty state
		local wins = vim.api.nvim_list_wins()
		if #wins > 0 then
			pcall(vim.api.nvim_set_current_win, wins[1])
		end
	end
end

--- Toggle the ask panel
function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

--- Focus the input window
function M.focus_input()
	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		vim.cmd("startinsert")
	end
end

--- Focus the output window
function M.focus_output()
	if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
		vim.api.nvim_set_current_win(state.output_win)
	end
end

--- Get input text
---@return string Input text
local function get_input_text()
	if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
		return ""
	end

	local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- Ignore placeholder
	if content:match("Type your question here") then
		return ""
	end

	return content
end

--- Clear input buffer
function M.clear_input()
	if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
	end
	state.referenced_files = {}
end

--- Append text to output buffer
---@param text string Text to append
---@param is_user boolean Whether this is user message
local function append_to_output(text, is_user)
	if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
		return
	end

	vim.bo[state.output_buf].modifiable = true

	local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)

	local timestamp = os.date("%H:%M")
	local header = is_user and "┌─ 👤 You [" .. timestamp .. "] ────────"
		or "┌─ 🤖 AI [" .. timestamp .. "] ──────────"

	local new_lines = { "", header, "│" }

	-- Add text lines with border
	for _, line in ipairs(vim.split(text, "\n")) do
		table.insert(new_lines, "│ " .. line)
	end

	table.insert(
		new_lines,
		"└─────────────────────────────────"
	)

	for _, line in ipairs(new_lines) do
		table.insert(lines, line)
	end

	vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, lines)
	vim.bo[state.output_buf].modifiable = false

	-- Scroll to bottom
	if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
		local line_count = vim.api.nvim_buf_line_count(state.output_buf)
		vim.api.nvim_win_set_cursor(state.output_win, { line_count, 0 })
	end
end

--- Build context from referenced files
---@return string Context string, number File count
local function build_file_context()
	local context = ""
	local file_count = 0

	for filename, filepath in pairs(state.referenced_files) do
		local content = utils.read_file(filepath)
		if content and content ~= "" then
			-- Detect language from extension
			local ext = vim.fn.fnamemodify(filepath, ":e")
			local lang = ext or "text"

			context = context .. "\n\n=== FILE: " .. filename .. " ===\n"
			context = context .. "Path: " .. filepath .. "\n"
			context = context .. "```" .. lang .. "\n" .. content .. "\n```\n"
			file_count = file_count + 1
		end
	end

	return context, file_count
end

--- Build context for the question
---@param intent? table Detected intent from intent module
---@return table Context object
local function build_context(intent)
	local context = {
		project_root = utils.get_project_root(),
		current_file = nil,
		current_content = nil,
		language = nil,
		referenced_files = state.referenced_files,
		brain_context = nil,
		indexer_context = nil,
	}

	-- Try to get current file context from the non-ask window
	local wins = vim.api.nvim_list_wins()
	for _, win in ipairs(wins) do
		if win ~= state.input_win and win ~= state.output_win then
			local buf = vim.api.nvim_win_get_buf(win)
			local filepath = vim.api.nvim_buf_get_name(buf)

			if filepath and filepath ~= "" and not filepath:match("%.coder%.") then
				context.current_file = filepath
				context.current_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
				context.language = vim.bo[buf].filetype
				break
			end
		end
	end

	-- Add brain context if intent needs it
	if intent and intent.needs_brain_context then
		local ok_brain, brain = pcall(require, "codetyper.brain")
		if ok_brain and brain.is_initialized() then
			context.brain_context = brain.get_context_for_llm({
				file = context.current_file,
				max_tokens = 1000,
			})
		end
	end

	-- Add indexer context if intent needs project-wide context
	if intent and intent.needs_project_context then
		local ok_indexer, indexer = pcall(require, "codetyper.indexer")
		if ok_indexer then
			context.indexer_context = indexer.get_context_for({
				file = context.current_file,
				prompt = "", -- Will be filled later
				intent = intent,
			})
		end
	end

	return context
end

--- Append exploration log to output buffer
---@param msg string
---@param level string
local function append_exploration_log(msg, level)
	if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
		return
	end

	vim.schedule(function()
		if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
			return
		end

		vim.bo[state.output_buf].modifiable = true

		local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)

		-- Format based on level
		local formatted = msg
		if level == "progress" then
			formatted = msg
		elseif level == "debug" then
			formatted = msg
		elseif level == "file" then
			formatted = msg
		end

		table.insert(lines, formatted)

		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, lines)
		vim.bo[state.output_buf].modifiable = false

		-- Scroll to bottom
		if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
			local line_count = vim.api.nvim_buf_line_count(state.output_buf)
			pcall(vim.api.nvim_win_set_cursor, state.output_win, { line_count, 0 })
		end
	end)
end

--- Continue submission after exploration
---@param question string
---@param intent table
---@param context table
---@param file_context string
---@param file_count number
---@param exploration_result table|nil
local function continue_submit(question, intent, context, file_context, file_count, exploration_result)
	-- Get prompt type based on intent
	local ok_intent, intent_module = pcall(require, "codetyper.ask.intent")
	local prompt_type = "ask"
	if ok_intent then
		prompt_type = intent_module.get_prompt_type(intent)
	end

	-- Build system prompt using prompts module
	local prompts = require("codetyper.prompts")
	local system_prompt = prompts.system[prompt_type] or prompts.system.ask

	if context.current_file then
		system_prompt = system_prompt .. "\n\nCurrent open file: " .. context.current_file
		system_prompt = system_prompt .. "\nLanguage: " .. (context.language or "unknown")
	end

	-- Add exploration context if available
	if exploration_result then
		local ok_explorer, explorer = pcall(require, "codetyper.ask.explorer")
		if ok_explorer then
			local explore_context = explorer.build_context(exploration_result)
			system_prompt = system_prompt .. "\n\n=== PROJECT EXPLORATION RESULTS ===\n"
			system_prompt = system_prompt .. explore_context
			system_prompt = system_prompt .. "\n=== END EXPLORATION ===\n"
		end
	end

	-- Add brain context (learned patterns, conventions)
	if context.brain_context and context.brain_context ~= "" then
		system_prompt = system_prompt .. "\n\n=== LEARNED PROJECT KNOWLEDGE ===\n"
		system_prompt = system_prompt .. context.brain_context
		system_prompt = system_prompt .. "\n=== END LEARNED KNOWLEDGE ===\n"
	end

	-- Add indexer context (project structure, symbols)
	if context.indexer_context then
		local idx_ctx = context.indexer_context
		if idx_ctx.project_type and idx_ctx.project_type ~= "unknown" then
			system_prompt = system_prompt .. "\n\nProject type: " .. idx_ctx.project_type
		end
		if idx_ctx.relevant_symbols and next(idx_ctx.relevant_symbols) then
			system_prompt = system_prompt .. "\n\nRelevant symbols in project:"
			for symbol, files in pairs(idx_ctx.relevant_symbols) do
				system_prompt = system_prompt .. "\n  - " .. symbol .. " (in: " .. table.concat(files, ", ") .. ")"
			end
		end
		if idx_ctx.patterns and #idx_ctx.patterns > 0 then
			system_prompt = system_prompt .. "\n\nProject patterns/memories:"
			for _, pattern in ipairs(idx_ctx.patterns) do
				system_prompt = system_prompt .. "\n  - " .. (pattern.summary or pattern.content or "")
			end
		end
	end

	-- Add to history
	table.insert(state.history, { role = "user", content = question })

	-- Show loading indicator
	append_to_output("", false)
	append_to_output("⏳ Generating response...", false)

	-- Get LLM client and generate response
	local ok, llm = pcall(require, "codetyper.llm")
	if not ok then
		append_to_output("❌ Error: LLM module not loaded", false)
		return
	end

	local client = llm.get_client()

	-- Build full prompt WITH file contents
	local full_prompt = question
	if file_context ~= "" then
		full_prompt = "USER QUESTION: "
			.. question
			.. "\n\n"
			.. "ATTACHED FILE CONTENTS (please analyze these):"
			.. file_context
	end

	-- Also add current file if no files were explicitly attached
	if file_count == 0 and context.current_content and context.current_content ~= "" then
		full_prompt = "USER QUESTION: "
			.. question
			.. "\n\n"
			.. "CURRENT FILE ("
			.. (context.current_file or "unknown")
			.. "):\n```\n"
			.. context.current_content
			.. "\n```"
	end

	-- Add exploration summary to prompt if available
	if exploration_result then
		full_prompt = full_prompt
			.. "\n\nPROJECT EXPLORATION COMPLETE: "
			.. exploration_result.total_files
			.. " files analyzed. "
			.. "Project type: "
			.. exploration_result.project.language
			.. " ("
			.. (exploration_result.project.framework or exploration_result.project.type)
			.. ")"
	end

	local request_context = {
		file_content = file_context ~= "" and file_context or context.current_content,
		language = context.language,
		prompt_type = prompt_type,
		file_path = context.current_file,
	}

	client.generate(full_prompt, request_context, function(response, err)
		-- Remove loading indicator
		if state.output_buf and vim.api.nvim_buf_is_valid(state.output_buf) then
			vim.bo[state.output_buf].modifiable = true
			local lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
			-- Remove last few lines (the thinking message)
			local to_remove = 0
			for i = #lines, 1, -1 do
				if lines[i]:match("Generating") or lines[i]:match("^[│└┌─]") or lines[i] == "" then
					to_remove = to_remove + 1
					if lines[i]:match("┌") or to_remove >= 5 then
						break
					end
				else
					break
				end
			end
			for _ = 1, math.min(to_remove, 5) do
				table.remove(lines)
			end
			vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, lines)
			vim.bo[state.output_buf].modifiable = false
		end

		if err then
			append_to_output("❌ Error: " .. err, false)
			return
		end

		if response then
			-- Add to history
			table.insert(state.history, { role = "assistant", content = response })
			-- Display response
			append_to_output(response, false)
		else
			append_to_output("❌ No response received", false)
		end

		-- Focus back to input
		M.focus_input()
	end)
end

--- Submit the question to LLM
function M.submit()
	local question = get_input_text()

	if not question or question:match("^%s*$") then
		utils.notify("Please enter a question", vim.log.levels.WARN)
		M.focus_input()
		return
	end

	-- Detect intent from prompt
	local ok_intent, intent_module = pcall(require, "codetyper.ask.intent")
	local intent = nil
	if ok_intent then
		intent = intent_module.detect(question)
	else
		-- Fallback intent
		intent = {
			type = "ask",
			confidence = 0.5,
			needs_project_context = false,
			needs_brain_context = true,
			needs_exploration = false,
		}
	end

	-- Build context BEFORE clearing input (to preserve file references)
	local context = build_context(intent)
	local file_context, file_count = build_file_context()

	-- Build display message (without full file contents)
	local display_question = question
	if file_count > 0 then
		display_question = question .. "\n📎 " .. file_count .. " file(s) attached"
	end
	-- Show detected intent if not standard ask
	if intent.type ~= "ask" then
		display_question = display_question .. "\n🎯 " .. intent.type:upper() .. " mode"
	end
	-- Show exploration indicator
	if intent.needs_exploration then
		display_question = display_question .. "\n🔍 Project exploration required"
	end

	-- Add user message to output
	append_to_output(display_question, true)

	-- Clear input and references AFTER building context
	M.clear_input()

	-- Check if exploration is needed
	if intent.needs_exploration then
		local ok_explorer, explorer = pcall(require, "codetyper.ask.explorer")
		if ok_explorer then
			local root = utils.get_project_root()
			if root then
				-- Start exploration with logging
				append_to_output("", false)
				explorer.explore(root, append_exploration_log, function(exploration_result)
					-- After exploration completes, continue with LLM request
					continue_submit(question, intent, context, file_context, file_count, exploration_result)
				end)
				return
			end
		end
	end

	-- No exploration needed, continue directly
	continue_submit(question, intent, context, file_context, file_count, nil)
end

--- Clear chat history
function M.clear_history()
	state.history = {}
	state.referenced_files = {}

	if state.output_buf and vim.api.nvim_buf_is_valid(state.output_buf) then
		local header = {
			"╔═════════════════════════════════╗",
			"║       [ASK MODE] Q&A Chat       ║",
			"╠═════════════════════════════════╣",
			"║ Ask about code or concepts      ║",
			"║                                 ║",
			"║ @ → attach file                 ║",
			"║ C-Enter → send                  ║",
			"║ C-n → new chat                  ║",
			"║ C-f → add current file          ║",
			"║ L → toggle LLM logs             ║",
			"║ :CoderType → switch mode        ║",
			"║ q → close │ K/J → jump          ║",
			"╚═════════════════════════════════╝",
			"",
		}
		vim.bo[state.output_buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, header)
		vim.bo[state.output_buf].modifiable = false
	end

	utils.notify("Chat history cleared")
end

--- Start a new chat (clears history and input)
function M.new_chat()
	-- Clear the input
	M.clear_input()
	-- Clear the history
	M.clear_history()
	-- Focus the input
	M.focus_input()
	utils.notify("Started new chat")
end

--- Include current file context in input
function M.include_file_context()
	local context = build_context()

	if not context.current_file then
		utils.notify("No file context available", vim.log.levels.WARN)
		return
	end

	local filename = vim.fn.fnamemodify(context.current_file, ":t")
	M.add_file_reference(context.current_file, filename)
end

--- Copy last assistant response to clipboard
function M.copy_last_response()
	for i = #state.history, 1, -1 do
		if state.history[i].role == "assistant" then
			vim.fn.setreg("+", state.history[i].content)
			utils.notify("Response copied to clipboard")
			return
		end
	end
	utils.notify("No response to copy", vim.log.levels.WARN)
end

--- Show chat mode switcher modal
function M.show_chat_switcher()
	local switcher = require("codetyper.chat_switcher")
	switcher.show()
end
--- Check if ask panel is open (validates window state)
---@return boolean
function M.is_open()
	-- Verify windows are actually valid, not just the flag
	if state.is_open then
		local output_valid = state.output_win and vim.api.nvim_win_is_valid(state.output_win)
		local input_valid = state.input_win and vim.api.nvim_win_is_valid(state.input_win)

		-- If either window is invalid, reset the state
		if not output_valid or not input_valid then
			state.is_open = false
			state.output_win = nil
			state.input_win = nil
			state.target_width = nil
			-- Clean up autocmd
			if ask_augroup then
				pcall(vim.api.nvim_del_augroup_by_id, ask_augroup)
				ask_augroup = nil
			end
		end
	end

	return state.is_open
end

--- Get chat history
---@return table History
function M.get_history()
	return state.history
end

--- Toggle LLM log visibility in chat
---@return boolean New state
function M.toggle_logs()
	state.show_logs = not state.show_logs
	utils.notify("LLM logs " .. (state.show_logs and "enabled" or "disabled"))
	return state.show_logs
end

--- Check if logs are enabled
---@return boolean
function M.logs_enabled()
	return state.show_logs
end

return M
