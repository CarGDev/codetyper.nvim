---@mod codetyper.core.thinking_placeholder In-buffer gray "thinking" text
---@brief [[
--- Inserts @thinking .... end thinking at the injection line (grayed out),
--- then replace it with the actual code when the response arrives.
---@brief ]]

local M = {}

local marks = require("codetyper.core.marks")

local PLACEHOLDER_TEXT = "@thinking .... end thinking"
local ns_highlight = vim.api.nvim_create_namespace("codetyper.thinking_placeholder")

--- event_id -> { start_mark, end_mark, bufnr } for the placeholder line
local placeholders = {}

--- 99-style inline: event_id -> { bufnr, nsid, extmark_id, throbber } for virtual-text-only "Thinking..."
local ns_inline = vim.api.nvim_create_namespace("codetyper.thinking_inline")
local inline_status = {}

--- Insert gray placeholder at the injection range in the target buffer.
--- Replaces the range (prompt/scope) with one line "@thinking .... end thinking" and grays it out.
---@param event table PromptEvent with range, scope_range, target_path
---@return boolean success
function M.insert(event)
	if not event or not event.range then
		return false
	end
	local range = event.scope_range or event.range
	local target_bufnr = vim.fn.bufnr(event.target_path)
	if target_bufnr == -1 then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf) == event.target_path then
				target_bufnr = buf
				break
			end
		end
	end
	if target_bufnr == -1 or not vim.api.nvim_buf_is_valid(target_bufnr) then
		target_bufnr = vim.fn.bufadd(event.target_path)
		if target_bufnr > 0 then
			vim.fn.bufload(target_bufnr)
		end
	end
	if target_bufnr <= 0 or not vim.api.nvim_buf_is_valid(target_bufnr) then
		return false
	end

	local line_count = vim.api.nvim_buf_line_count(target_bufnr)
	local end_line = range.end_line
	-- Include next line if it's only "}" (or whitespace + "}") so we don't leave a stray closing brace
	if end_line < line_count then
		local next_line = vim.api.nvim_buf_get_lines(target_bufnr, end_line, end_line + 1, false)
		if next_line and next_line[1] and next_line[1]:match("^%s*}$") then
			end_line = end_line + 1
		end
	end

	local start_row_0 = range.start_line - 1
	local end_row_0 = end_line
	-- Replace range with single placeholder line
	vim.api.nvim_buf_set_lines(target_bufnr, start_row_0, end_row_0, false, { PLACEHOLDER_TEXT })
	-- Gray out: extmark over the whole line
	vim.api.nvim_buf_set_extmark(target_bufnr, ns_highlight, start_row_0, 0, {
		end_row = start_row_0 + 1,
		hl_group = "Comment",
		hl_eol = true,
	})
	-- Store marks for this placeholder so patch can replace it
	local start_mark = marks.mark_point(target_bufnr, start_row_0, 0)
	local end_mark = marks.mark_point(target_bufnr, start_row_0, #PLACEHOLDER_TEXT)
	placeholders[event.id] = {
		start_mark = start_mark,
		end_mark = end_mark,
		bufnr = target_bufnr,
	}
	return true
end

--- Get placeholder marks for an event (so patch can replace that range with code).
---@param event_id string
---@return table|nil { start_mark, end_mark, bufnr } or nil
function M.get(event_id)
	return placeholders[event_id]
end

--- Clear placeholder entry after applying (and optionally delete marks).
---@param event_id string
function M.clear(event_id)
	local p = placeholders[event_id]
	if p then
		marks.delete(p.start_mark)
		marks.delete(p.end_mark)
		placeholders[event_id] = nil
	end
end

--- Remove placeholder from buffer (e.g. on failure/cancel) and clear. Replaces placeholder line with empty line.
---@param event_id string
function M.remove_on_failure(event_id)
	local p = placeholders[event_id]
	if not p or not p.bufnr or not vim.api.nvim_buf_is_valid(p.bufnr) then
		M.clear(event_id)
		return
	end
	if marks.is_valid(p.start_mark) and marks.is_valid(p.end_mark) then
		local sr, sc, er, ec = marks.range_to_vim(p.start_mark, p.end_mark)
		if sr ~= nil then
			vim.api.nvim_buf_set_text(p.bufnr, sr, sc, er, ec, { "" })
		end
	end
	M.clear(event_id)
end

--- 99-style: show "⠋ Thinking..." as virtual text at the line above the selection (no buffer change).
--- Use for inline requests where we must not insert placeholder (e.g. SEARCH/REPLACE).
---@param event table PromptEvent with id, range, target_path
function M.start_inline(event)
	if not event or not event.id or not event.range then
		return
	end
	local range = event.range
	local target_bufnr = vim.fn.bufnr(event.target_path)
	if target_bufnr == -1 then
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf) == event.target_path then
				target_bufnr = buf
				break
			end
		end
	end
	if target_bufnr <= 0 or not vim.api.nvim_buf_is_valid(target_bufnr) then
		return
	end
	-- Mark at line above range (99: mark_above_range). If start is line 1 (0-indexed 0), use row 0.
	local start_row_0 = math.max(0, range.start_line - 2) -- 1-based start_line -> 0-based, then one line up
	local col = 0
	local extmark_id = vim.api.nvim_buf_set_extmark(target_bufnr, ns_inline, start_row_0, col, {
		virt_lines = { { { " Implementing", "Comment" } } },
	})
	local Throbber = require("codetyper.adapters.nvim.ui.throbber")
	local throb = Throbber.new(function(icon)
		if not inline_status[event.id] then
			return
		end
		local ent = inline_status[event.id]
		if not ent.bufnr or not vim.api.nvim_buf_is_valid(ent.bufnr) then
			return
		end
		local ok = pcall(vim.api.nvim_buf_set_extmark, ent.bufnr, ns_inline, start_row_0, col, {
			id = ent.extmark_id,
			virt_lines = { { { icon .. " Implementing", "Comment" } } },
		})
		if not ok then
			M.clear_inline(event.id)
		end
	end)
	inline_status[event.id] = {
		bufnr = target_bufnr,
		nsid = ns_inline,
		extmark_id = extmark_id,
		throbber = throb,
		start_row_0 = start_row_0,
		col = col,
	}
	throb:start()
end

--- Clear 99-style inline virtual text (call when worker completes).
---@param event_id string
function M.clear_inline(event_id)
	local ent = inline_status[event_id]
	if not ent then
		return
	end
	if ent.throbber then
		ent.throbber:stop()
	end
	if ent.bufnr and vim.api.nvim_buf_is_valid(ent.bufnr) and ent.extmark_id then
		pcall(vim.api.nvim_buf_del_extmark, ent.bufnr, ns_inline, ent.extmark_id)
	end
	inline_status[event_id] = nil
end

return M
