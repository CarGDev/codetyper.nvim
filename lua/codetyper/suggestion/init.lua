---@mod codetyper.suggestion Inline ghost text suggestions
---@brief [[
--- Provides Copilot-style inline suggestions with ghost text.
--- Uses Copilot when available, falls back to codetyper's own suggestions.
--- Shows suggestions as grayed-out text that can be accepted with Tab.
---@brief ]]

local M = {}

---@class SuggestionState
---@field current_suggestion string|nil Current suggestion text
---@field suggestions string[] List of available suggestions
---@field current_index number Current suggestion index
---@field extmark_id number|nil Virtual text extmark ID
---@field bufnr number|nil Buffer where suggestion is shown
---@field line number|nil Line where suggestion is shown
---@field col number|nil Column where suggestion starts
---@field timer any|nil Debounce timer
---@field using_copilot boolean Whether currently using copilot

local state = {
	current_suggestion = nil,
	suggestions = {},
	current_index = 0,
	extmark_id = nil,
	bufnr = nil,
	line = nil,
	col = nil,
	timer = nil,
	using_copilot = false,
}

--- Namespace for virtual text
local ns = vim.api.nvim_create_namespace("codetyper_suggestion")

--- Highlight group for ghost text
local hl_group = "CmpGhostText"

--- Configuration
local config = {
	enabled = true,
	auto_trigger = true,
	debounce = 150,
	use_copilot = true, -- Use copilot when available
	keymap = {
		accept = "<Tab>",
		next = "<M-]>",
		prev = "<M-[>",
		dismiss = "<C-]>",
	},
}

--- Check if copilot is available and enabled
---@return boolean, table|nil available, copilot_suggestion module
local function get_copilot()
	if not config.use_copilot then
		return false, nil
	end

	local ok, copilot_suggestion = pcall(require, "copilot.suggestion")
	if not ok then
		return false, nil
	end

	-- Check if copilot suggestion is enabled
	local ok_client, copilot_client = pcall(require, "copilot.client")
	if ok_client and copilot_client.is_disabled and copilot_client.is_disabled() then
		return false, nil
	end

	return true, copilot_suggestion
end

--- Check if suggestion is visible (copilot or codetyper)
---@return boolean
function M.is_visible()
	-- Check copilot first
	local copilot_ok, copilot_suggestion = get_copilot()
	if copilot_ok and copilot_suggestion.is_visible() then
		state.using_copilot = true
		return true
	end

	-- Check codetyper's own suggestion
	state.using_copilot = false
	return state.extmark_id ~= nil and state.current_suggestion ~= nil
end

--- Clear the current suggestion
function M.dismiss()
	-- Dismiss copilot if active
	local copilot_ok, copilot_suggestion = get_copilot()
	if copilot_ok and copilot_suggestion.is_visible() then
		copilot_suggestion.dismiss()
	end

	-- Clear codetyper's suggestion
	if state.extmark_id and state.bufnr then
		pcall(vim.api.nvim_buf_del_extmark, state.bufnr, ns, state.extmark_id)
	end

	state.current_suggestion = nil
	state.suggestions = {}
	state.current_index = 0
	state.extmark_id = nil
	state.bufnr = nil
	state.line = nil
	state.col = nil
	state.using_copilot = false
end

--- Display suggestion as ghost text
---@param suggestion string The suggestion to display
local function display_suggestion(suggestion)
	if not suggestion or suggestion == "" then
		return
	end

	M.dismiss()

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] - 1
	local col = cursor[2]

	-- Split suggestion into lines
	local lines = vim.split(suggestion, "\n", { plain = true })

	-- Build virtual text
	local virt_text = {}
	local virt_lines = {}

	-- First line goes inline
	if #lines > 0 then
		virt_text = { { lines[1], hl_group } }
	end

	-- Remaining lines go below
	for i = 2, #lines do
		table.insert(virt_lines, { { lines[i], hl_group } })
	end

	-- Create extmark with virtual text
	local opts = {
		virt_text = virt_text,
		virt_text_pos = "overlay",
		hl_mode = "combine",
	}

	if #virt_lines > 0 then
		opts.virt_lines = virt_lines
	end

	state.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, line, col, opts)
	state.bufnr = bufnr
	state.line = line
	state.col = col
	state.current_suggestion = suggestion
end

--- Accept the current suggestion
---@return boolean Whether a suggestion was accepted
function M.accept()
	-- Check copilot first
	local copilot_ok, copilot_suggestion = get_copilot()
	if copilot_ok and copilot_suggestion.is_visible() then
		copilot_suggestion.accept()
		state.using_copilot = false
		return true
	end

	-- Accept codetyper's suggestion
	if not M.is_visible() then
		return false
	end

	local suggestion = state.current_suggestion
	local bufnr = state.bufnr
	local line = state.line
	local col = state.col

	M.dismiss()

	if suggestion and bufnr and line ~= nil and col ~= nil then
		-- Get current line content
		local current_line = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""

		-- Split suggestion into lines
		local suggestion_lines = vim.split(suggestion, "\n", { plain = true })

		if #suggestion_lines == 1 then
			-- Single line - insert at cursor
			local new_line = current_line:sub(1, col) .. suggestion .. current_line:sub(col + 1)
			vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { new_line })
			-- Move cursor to end of inserted text
			vim.api.nvim_win_set_cursor(0, { line + 1, col + #suggestion })
		else
			-- Multi-line - insert at cursor
			local first_line = current_line:sub(1, col) .. suggestion_lines[1]
			local last_line = suggestion_lines[#suggestion_lines] .. current_line:sub(col + 1)

			local new_lines = { first_line }
			for i = 2, #suggestion_lines - 1 do
				table.insert(new_lines, suggestion_lines[i])
			end
			table.insert(new_lines, last_line)

			vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, new_lines)
			-- Move cursor to end of last line
			vim.api.nvim_win_set_cursor(0, { line + #new_lines, #suggestion_lines[#suggestion_lines] })
		end

		return true
	end

	return false
end

--- Show next suggestion
function M.next()
	-- Check copilot first
	local copilot_ok, copilot_suggestion = get_copilot()
	if copilot_ok and copilot_suggestion.is_visible() then
		copilot_suggestion.next()
		return
	end

	-- Codetyper's suggestions
	if #state.suggestions <= 1 then
		return
	end

	state.current_index = (state.current_index % #state.suggestions) + 1
	display_suggestion(state.suggestions[state.current_index])
end

--- Show previous suggestion
function M.prev()
	-- Check copilot first
	local copilot_ok, copilot_suggestion = get_copilot()
	if copilot_ok and copilot_suggestion.is_visible() then
		copilot_suggestion.prev()
		return
	end

	-- Codetyper's suggestions
	if #state.suggestions <= 1 then
		return
	end

	state.current_index = state.current_index - 1
	if state.current_index < 1 then
		state.current_index = #state.suggestions
	end
	display_suggestion(state.suggestions[state.current_index])
end

--- Get suggestions from brain/indexer
---@param prefix string Current word prefix
---@param context table Context info
---@return string[] suggestions
local function get_suggestions(prefix, context)
	local suggestions = {}

	-- Get completions from brain
	local ok_brain, brain = pcall(require, "codetyper.brain")
	if ok_brain and brain.is_initialized and brain.is_initialized() then
		local result = brain.query({
			query = prefix,
			max_results = 5,
			types = { "pattern" },
		})

		if result and result.nodes then
			for _, node in ipairs(result.nodes) do
				if node.c and node.c.code then
					table.insert(suggestions, node.c.code)
				end
			end
		end
	end

	-- Get completions from indexer
	local ok_indexer, indexer = pcall(require, "codetyper.indexer")
	if ok_indexer then
		local index = indexer.load_index()
		if index and index.symbols then
			for symbol, _ in pairs(index.symbols) do
				if symbol:lower():find(prefix:lower(), 1, true) and symbol ~= prefix then
					-- Just complete the symbol name
					local completion = symbol:sub(#prefix + 1)
					if completion ~= "" then
						table.insert(suggestions, completion)
					end
				end
			end
		end
	end

	-- Buffer-based completions
	local bufnr = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local seen = {}

	for _, line in ipairs(lines) do
		for word in line:gmatch("[%a_][%w_]*") do
			if
				#word > #prefix
				and word:lower():find(prefix:lower(), 1, true) == 1
				and not seen[word]
				and word ~= prefix
			then
				seen[word] = true
				local completion = word:sub(#prefix + 1)
				if completion ~= "" then
					table.insert(suggestions, completion)
				end
			end
		end
	end

	return suggestions
end

--- Trigger suggestion generation
function M.trigger()
	if not config.enabled then
		return
	end

	-- If copilot is available and has a suggestion, don't show codetyper's
	local copilot_ok, copilot_suggestion = get_copilot()
	if copilot_ok and copilot_suggestion.is_visible() then
		-- Copilot is handling suggestions
		state.using_copilot = true
		return
	end

	-- Cancel existing timer
	if state.timer then
		state.timer:stop()
		state.timer = nil
	end

	-- Get current context
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	local col = cursor[2]
	local before_cursor = line:sub(1, col)

	-- Extract prefix (word being typed)
	local prefix = before_cursor:match("[%a_][%w_]*$") or ""

	if #prefix < 2 then
		M.dismiss()
		return
	end

	-- Debounce - wait a bit longer to let copilot try first
	local debounce_time = copilot_ok and (config.debounce + 200) or config.debounce

	state.timer = vim.defer_fn(function()
		-- Check again if copilot has shown something
		if copilot_ok and copilot_suggestion.is_visible() then
			state.using_copilot = true
			state.timer = nil
			return
		end

		local suggestions = get_suggestions(prefix, {
			line = line,
			col = col,
			bufnr = vim.api.nvim_get_current_buf(),
		})

		if #suggestions > 0 then
			state.suggestions = suggestions
			state.current_index = 1
			display_suggestion(suggestions[1])
		else
			M.dismiss()
		end

		state.timer = nil
	end, debounce_time)
end

--- Setup keymaps
local function setup_keymaps()
	-- Accept with Tab (only when suggestion visible)
	vim.keymap.set("i", config.keymap.accept, function()
		if M.is_visible() then
			M.accept()
			return ""
		end
		-- Fallback to normal Tab behavior
		return vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
	end, { expr = true, silent = true, desc = "Accept codetyper suggestion" })

	-- Next suggestion
	vim.keymap.set("i", config.keymap.next, function()
		M.next()
	end, { silent = true, desc = "Next codetyper suggestion" })

	-- Previous suggestion
	vim.keymap.set("i", config.keymap.prev, function()
		M.prev()
	end, { silent = true, desc = "Previous codetyper suggestion" })

	-- Dismiss
	vim.keymap.set("i", config.keymap.dismiss, function()
		M.dismiss()
	end, { silent = true, desc = "Dismiss codetyper suggestion" })
end

--- Setup autocmds for auto-trigger
local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("CodetypeSuggestion", { clear = true })

	-- Trigger on text change in insert mode
	if config.auto_trigger then
		vim.api.nvim_create_autocmd("TextChangedI", {
			group = group,
			callback = function()
				M.trigger()
			end,
		})
	end

	-- Dismiss on leaving insert mode
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		callback = function()
			M.dismiss()
		end,
	})

	-- Dismiss on cursor move (not from typing)
	vim.api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = function()
			-- Only dismiss if cursor moved significantly
			if state.line ~= nil then
				local cursor = vim.api.nvim_win_get_cursor(0)
				if cursor[1] - 1 ~= state.line then
					M.dismiss()
				end
			end
		end,
	})
end

--- Setup highlight group
local function setup_highlights()
	-- Use Comment highlight or define custom ghost text style
	vim.api.nvim_set_hl(0, hl_group, { link = "Comment" })
end

--- Setup the suggestion system
---@param opts? table Configuration options
function M.setup(opts)
	if opts then
		config = vim.tbl_deep_extend("force", config, opts)
	end

	setup_highlights()
	setup_keymaps()
	setup_autocmds()
end

--- Enable suggestions
function M.enable()
	config.enabled = true
end

--- Disable suggestions
function M.disable()
	config.enabled = false
	M.dismiss()
end

--- Toggle suggestions
function M.toggle()
	if config.enabled then
		M.disable()
	else
		M.enable()
	end
end

return M
