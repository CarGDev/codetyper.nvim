---@mod codetyper.executor.write Search/replace operations
---@brief [[
--- Pure string operations for applying search/replace edits.
--- No validation of correctness - just apply the transformation.
---@brief ]]

local M = {}

--- Apply a search/replace edit to content
---@param content string Original file content
---@param search string Text to find
---@param replace string Text to replace with
---@return string|nil new_content
---@return string|nil error
function M.apply_search_replace(content, search, replace)
	if not content then
		return nil, "No content provided"
	end

	-- Handle empty search (new file or append)
	if not search or search == "" then
		return replace, nil
	end

	-- Try exact match first
	local new_content, count = content:gsub(search, replace, 1)

	if count > 0 then
		return new_content, nil
	end

	-- Try with normalized line endings
	local norm_search = search:gsub("\r\n", "\n"):gsub("\r", "\n")
	local norm_content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
	new_content, count = norm_content:gsub(norm_search, replace, 1)

	if count > 0 then
		return new_content, nil
	end

	return nil, "Search text not found"
end

--- Apply multiple search/replace edits in sequence
---@param content string Original content
---@param edits table[] Array of {search: string, replace: string}
---@return string|nil new_content
---@return string|nil error
function M.apply_edits(content, edits)
	if not edits or #edits == 0 then
		return content, nil
	end

	local current = content
	for i, edit in ipairs(edits) do
		local result, err = M.apply_search_replace(current, edit.search, edit.replace)
		if err then
			return nil, string.format("Edit %d failed: %s", i, err)
		end
		current = result
	end

	return current, nil
end

--- Format a diff between two strings (simple unified diff)
---@param original string Original content
---@param modified string Modified content
---@return string diff
function M.format_diff(original, modified)
	local orig_lines = vim.split(original or "", "\n", { plain = true })
	local mod_lines = vim.split(modified or "", "\n", { plain = true })

	local diff_lines = {}
	table.insert(diff_lines, "--- original")
	table.insert(diff_lines, "+++ modified")

	-- Simple line-by-line comparison (not a real diff algorithm)
	local max_lines = math.max(#orig_lines, #mod_lines)

	for i = 1, max_lines do
		local orig = orig_lines[i]
		local mod = mod_lines[i]

		if orig and mod then
			if orig ~= mod then
				table.insert(diff_lines, "-" .. orig)
				table.insert(diff_lines, "+" .. mod)
			else
				table.insert(diff_lines, " " .. orig)
			end
		elseif orig then
			table.insert(diff_lines, "-" .. orig)
		elseif mod then
			table.insert(diff_lines, "+" .. mod)
		end
	end

	return table.concat(diff_lines, "\n")
end

return M
