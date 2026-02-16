---@mod codetyper.core.marks Extmarks for tracking buffer positions (99-style)
---@brief [[
--- Positions survive user edits so we can apply patches at the right place
--- after the user has been typing while the request was "thinking".
---@brief ]]

local M = {}

local nsid = vim.api.nvim_create_namespace("codetyper.marks")

---@class Mark
---@field id number Extmark id
---@field buffer number Buffer number
---@field nsid number Namespace id

--- Create an extmark at (row_0, col_0). 0-based indexing for nvim API.
---@param buffer number
---@param row_0 number 0-based row
---@param col_0 number 0-based column
---@return Mark
function M.mark_point(buffer, row_0, col_0)
	if not vim.api.nvim_buf_is_valid(buffer) then
		return { id = nil, buffer = buffer, nsid = nsid }
	end
	local line_count = vim.api.nvim_buf_line_count(buffer)
	if line_count == 0 or row_0 < 0 or row_0 >= line_count then
		return { id = nil, buffer = buffer, nsid = nsid }
	end
	local id = vim.api.nvim_buf_set_extmark(buffer, nsid, row_0, col_0, {})
	return {
		id = id,
		buffer = buffer,
		nsid = nsid,
	}
end

--- Create marks for a range. start/end are 1-based line numbers; end_col_0 is 0-based column on end line.
---@param buffer number
---@param start_line number 1-based start line
---@param end_line number 1-based end line
---@param end_col_0 number|nil 0-based column on end line (default: 0)
---@return Mark start_mark
---@return Mark end_mark
function M.mark_range(buffer, start_line, end_line, end_col_0)
	end_col_0 = end_col_0 or 0
	local start_mark = M.mark_point(buffer, start_line - 1, 0)
	local end_mark = M.mark_point(buffer, end_line - 1, end_col_0)
	return start_mark, end_mark
end

--- Get current 0-based (row, col) of a mark. Returns nil if mark invalid.
---@param mark Mark
---@return number|nil row_0
---@return number|nil col_0
function M.get_position(mark)
	if not mark or not mark.id or not vim.api.nvim_buf_is_valid(mark.buffer) then
		return nil, nil
	end
	local pos = vim.api.nvim_buf_get_extmark_by_id(mark.buffer, mark.nsid, mark.id, {})
	if not pos or #pos < 2 then
		return nil, nil
	end
	return pos[1], pos[2]
end

--- Check if mark still exists and buffer valid.
---@param mark Mark
---@return boolean
function M.is_valid(mark)
	if not mark or not mark.id then
		return false
	end
	local row, col = M.get_position(mark)
	return row ~= nil and col ~= nil
end

--- Get current range as 0-based (start_row, start_col, end_row, end_col) for nvim_buf_set_text. Returns nil if any mark invalid.
---@param start_mark Mark
---@param end_mark Mark
---@return number|nil, number|nil, number|nil, number|nil
function M.range_to_vim(start_mark, end_mark)
	local sr, sc = M.get_position(start_mark)
	local er, ec = M.get_position(end_mark)
	if sr == nil or er == nil then
		return nil, nil, nil, nil
	end
	return sr, sc, er, ec
end

--- Replace text between two marks with lines (like 99 Range:replace_text). Uses current positions from extmarks.
---@param buffer number
---@param start_mark Mark
---@param end_mark Mark
---@param lines string[]
---@return boolean success
function M.replace_text(buffer, start_mark, end_mark, lines)
	local sr, sc, er, ec = M.range_to_vim(start_mark, end_mark)
	if sr == nil then
		return false
	end
	if not vim.api.nvim_buf_is_valid(buffer) then
		return false
	end
	vim.api.nvim_buf_set_text(buffer, sr, sc, er, ec, lines)
	return true
end

--- Delete extmark (cleanup).
---@param mark Mark
function M.delete(mark)
	if not mark or not mark.id or not vim.api.nvim_buf_is_valid(mark.buffer) then
		return
	end
	pcall(vim.api.nvim_buf_del_extmark, mark.buffer, mark.nsid, mark.id)
end

return M
