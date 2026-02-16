---@mod codetyper.ui.thinking Thinking indicator (99-style status window + throbber)
---@brief [[
--- Shows a small top-right floating window with animated spinner while prompts are processing.
--- Replaces opening the full logs panel during code generation.
---@brief ]]

local M = {}

local throbber = require("codetyper.adapters.nvim.ui.throbber")
local queue = require("codetyper.core.events.queue")

---@class ThinkingState
---@field win_id number|nil
---@field buf_id number|nil
---@field throbber Throbber|nil
---@field queue_listener_id number|nil
---@field timer number|nil Defer timer for polling

local state = {
	win_id = nil,
	buf_id = nil,
	throbber = nil,
	queue_listener_id = nil,
	timer = nil,
}

local function get_ui_dimensions()
	local ui = vim.api.nvim_list_uis()[1]
	if ui then
		return ui.width, ui.height
	end
	return vim.o.columns, vim.o.lines
end

--- Top-right status window config (like 99)
local function status_window_config()
	local width, _ = get_ui_dimensions()
	local win_width = math.min(40, math.floor(width / 3))
	return {
		relative = "editor",
		row = 0,
		col = width,
		width = win_width,
		height = 2,
		anchor = "NE",
		style = "minimal",
		border = nil,
		zindex = 100,
	}
end

local function active_count()
	return queue.pending_count() + queue.processing_count()
end

local function close_window()
	if state.timer then
		pcall(vim.fn.timer_stop, state.timer)
		state.timer = nil
	end
	if state.throbber then
		state.throbber:stop()
		state.throbber = nil
	end
	if state.queue_listener_id then
		queue.remove_listener(state.queue_listener_id)
		state.queue_listener_id = nil
	end
	if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
		vim.api.nvim_win_close(state.win_id, true)
	end
	if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
		vim.api.nvim_buf_delete(state.buf_id, { force = true })
	end
	state.win_id = nil
	state.buf_id = nil
end

local function update_display(icon, force)
	if not state.buf_id or not vim.api.nvim_buf_is_valid(state.buf_id) then
		return
	end
	local count = active_count()
	if count <= 0 and not force then
		return
	end
	local line = (count <= 1)
		and (icon .. " Thinking...")
		or (icon .. " Thinking... (" .. tostring(count) .. " requests)")
	vim.schedule(function()
		if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
			vim.bo[state.buf_id].modifiable = true
			vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, { line })
			vim.bo[state.buf_id].modifiable = false
		end
	end)
end

local function check_and_hide()
	if active_count() > 0 then
		return
	end
	close_window()
end

--- Ensure the thinking status window is shown and throbber is running.
--- Call when starting prompt processing (instead of logs_panel.ensure_open).
function M.ensure_shown()
	if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
		-- Already shown; throbber keeps running
		return
	end

	state.buf_id = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf_id].buftype = "nofile"
	vim.bo[state.buf_id].bufhidden = "wipe"
	vim.bo[state.buf_id].swapfile = false

	local config = status_window_config()
	state.win_id = vim.api.nvim_open_win(state.buf_id, false, config)
	vim.wo[state.win_id].wrap = true
	vim.wo[state.win_id].number = false
	vim.wo[state.win_id].relativenumber = false

	state.throbber = throbber.new(function(icon)
		update_display(icon)
		-- When active count drops to 0, hide after a short delay
		if active_count() <= 0 then
			vim.defer_fn(check_and_hide, 300)
		end
	end)
	state.throbber:start()

	-- Queue listener: when queue updates, check if we should hide
	state.queue_listener_id = queue.add_listener(function(_, _, _)
		vim.schedule(function()
			if active_count() <= 0 then
				vim.defer_fn(check_and_hide, 400)
			end
		end)
	end)

	-- Initial line (force show before enqueue so window is not empty)
	local icon = (state.throbber and state.throbber.icon_set and state.throbber.icon_set[1]) or "⠋"
	update_display(icon, true)
end

--- Force close the thinking window (e.g. on VimLeavePre).
function M.close()
	close_window()
end

--- Check if thinking window is currently visible.
---@return boolean
function M.is_shown()
	return state.win_id ~= nil and vim.api.nvim_win_is_valid(state.win_id)
end

--- Register autocmds for cleanup on exit.
function M.setup()
	local group = vim.api.nvim_create_augroup("CodetyperThinking", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			M.close()
		end,
		desc = "Close thinking window before exiting Neovim",
	})
end

return M
