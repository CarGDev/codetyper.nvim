---@mod codetyper.agent.tools.edit File editing tool with fallback matching
---@brief [[
--- Tool for making targeted edits to files using search/replace.
--- Implements multiple fallback strategies for robust matching.
--- Multi-strategy approach for reliable editing.
---@brief ]]

local Base = require("codetyper.agent.tools.base")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "edit"

M.description = [[Makes a targeted edit to a file by replacing text.

The old_string should match the content you want to replace. The tool uses multiple
matching strategies with fallbacks:
1. Exact match
2. Whitespace-normalized match
3. Indentation-flexible match
4. Line-trimmed match
5. Fuzzy anchor-based match

For creating new files, use old_string="" and provide the full content in new_string.
For large changes, consider using 'write' tool instead.]]

M.params = {
	{
		name = "path",
		description = "Path to the file to edit",
		type = "string",
	},
	{
		name = "old_string",
		description = "Text to find and replace (empty string to create new file or append)",
		type = "string",
	},
	{
		name = "new_string",
		description = "Text to replace with",
		type = "string",
	},
}

M.returns = {
	{
		name = "success",
		description = "Whether the edit was applied",
		type = "boolean",
	},
	{
		name = "error",
		description = "Error message if edit failed",
		type = "string",
		optional = true,
	},
}

M.requires_confirmation = false

--- Normalize line endings to LF
---@param str string
---@return string
local function normalize_line_endings(str)
	return str:gsub("\r\n", "\n"):gsub("\r", "\n")
end

--- Strategy 1: Exact match
---@param content string File content
---@param old_str string String to find
---@return number|nil start_pos
---@return number|nil end_pos
local function exact_match(content, old_str)
	local pos = content:find(old_str, 1, true)
	if pos then
		return pos, pos + #old_str - 1
	end
	return nil, nil
end

--- Strategy 2: Whitespace-normalized match
--- Collapses all whitespace to single spaces
---@param content string
---@param old_str string
---@return number|nil start_pos
---@return number|nil end_pos
local function whitespace_normalized_match(content, old_str)
	local function normalize_ws(s)
		return s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	end

	local norm_old = normalize_ws(old_str)
	local lines = vim.split(content, "\n")

	-- Try to find matching block
	for i = 1, #lines do
		local block = {}
		local block_start = nil

		for j = i, #lines do
			table.insert(block, lines[j])
			local block_text = table.concat(block, "\n")
			local norm_block = normalize_ws(block_text)

			if norm_block == norm_old then
				-- Found match
				local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
				local start_pos = #before + (i > 1 and 2 or 1)
				local end_pos = start_pos + #block_text - 1
				return start_pos, end_pos
			end

			-- If block is already longer than target, stop
			if #norm_block > #norm_old then
				break
			end
		end
	end

	return nil, nil
end

--- Strategy 3: Indentation-flexible match
--- Ignores leading whitespace differences
---@param content string
---@param old_str string
---@return number|nil start_pos
---@return number|nil end_pos
local function indentation_flexible_match(content, old_str)
	local function strip_indent(s)
		local lines = vim.split(s, "\n")
		local result = {}
		for _, line in ipairs(lines) do
			table.insert(result, line:gsub("^%s+", ""))
		end
		return table.concat(result, "\n")
	end

	local stripped_old = strip_indent(old_str)
	local lines = vim.split(content, "\n")
	local old_lines = vim.split(old_str, "\n")
	local num_old_lines = #old_lines

	for i = 1, #lines - num_old_lines + 1 do
		local block = vim.list_slice(lines, i, i + num_old_lines - 1)
		local block_text = table.concat(block, "\n")

		if strip_indent(block_text) == stripped_old then
			local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
			local start_pos = #before + (i > 1 and 2 or 1)
			local end_pos = start_pos + #block_text - 1
			return start_pos, end_pos
		end
	end

	return nil, nil
end

--- Strategy 4: Line-trimmed match
--- Trims each line before comparing
---@param content string
---@param old_str string
---@return number|nil start_pos
---@return number|nil end_pos
local function line_trimmed_match(content, old_str)
	local function trim_lines(s)
		local lines = vim.split(s, "\n")
		local result = {}
		for _, line in ipairs(lines) do
			table.insert(result, line:match("^%s*(.-)%s*$"))
		end
		return table.concat(result, "\n")
	end

	local trimmed_old = trim_lines(old_str)
	local lines = vim.split(content, "\n")
	local old_lines = vim.split(old_str, "\n")
	local num_old_lines = #old_lines

	for i = 1, #lines - num_old_lines + 1 do
		local block = vim.list_slice(lines, i, i + num_old_lines - 1)
		local block_text = table.concat(block, "\n")

		if trim_lines(block_text) == trimmed_old then
			local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
			local start_pos = #before + (i > 1 and 2 or 1)
			local end_pos = start_pos + #block_text - 1
			return start_pos, end_pos
		end
	end

	return nil, nil
end

--- Calculate Levenshtein distance between two strings
---@param s1 string
---@param s2 string
---@return number
local function levenshtein(s1, s2)
	local len1, len2 = #s1, #s2
	local matrix = {}

	for i = 0, len1 do
		matrix[i] = { [0] = i }
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	for i = 1, len1 do
		for j = 1, len2 do
			local cost = s1:sub(i, i) == s2:sub(j, j) and 0 or 1
			matrix[i][j] = math.min(
				matrix[i - 1][j] + 1,
				matrix[i][j - 1] + 1,
				matrix[i - 1][j - 1] + cost
			)
		end
	end

	return matrix[len1][len2]
end

--- Strategy 5: Fuzzy anchor-based match
--- Uses first and last lines as anchors, allows fuzzy matching in between
---@param content string
---@param old_str string
---@param threshold? number Similarity threshold (0-1), default 0.8
---@return number|nil start_pos
---@return number|nil end_pos
local function fuzzy_anchor_match(content, old_str, threshold)
	threshold = threshold or 0.8

	local old_lines = vim.split(old_str, "\n")
	if #old_lines < 2 then
		return nil, nil
	end

	local first_line = old_lines[1]:match("^%s*(.-)%s*$")
	local last_line = old_lines[#old_lines]:match("^%s*(.-)%s*$")
	local content_lines = vim.split(content, "\n")

	-- Find potential start positions
	local candidates = {}
	for i, line in ipairs(content_lines) do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed == first_line or (
			#first_line > 0 and
			1 - (levenshtein(trimmed, first_line) / math.max(#trimmed, #first_line)) >= threshold
		) then
			table.insert(candidates, i)
		end
	end

	-- For each candidate, look for matching end
	for _, start_idx in ipairs(candidates) do
		local expected_end = start_idx + #old_lines - 1
		if expected_end <= #content_lines then
			local end_line = content_lines[expected_end]:match("^%s*(.-)%s*$")
			if end_line == last_line or (
				#last_line > 0 and
				1 - (levenshtein(end_line, last_line) / math.max(#end_line, #last_line)) >= threshold
			) then
				-- Calculate positions
				local before = table.concat(vim.list_slice(content_lines, 1, start_idx - 1), "\n")
				local block = table.concat(vim.list_slice(content_lines, start_idx, expected_end), "\n")
				local start_pos = #before + (start_idx > 1 and 2 or 1)
				local end_pos = start_pos + #block - 1
				return start_pos, end_pos
			end
		end
	end

	return nil, nil
end

--- Try all matching strategies in order
---@param content string File content
---@param old_str string String to find
---@return number|nil start_pos
---@return number|nil end_pos
---@return string strategy_used
local function find_match(content, old_str)
	-- Strategy 1: Exact match
	local start_pos, end_pos = exact_match(content, old_str)
	if start_pos then
		return start_pos, end_pos, "exact"
	end

	-- Strategy 2: Whitespace-normalized
	start_pos, end_pos = whitespace_normalized_match(content, old_str)
	if start_pos then
		return start_pos, end_pos, "whitespace_normalized"
	end

	-- Strategy 3: Indentation-flexible
	start_pos, end_pos = indentation_flexible_match(content, old_str)
	if start_pos then
		return start_pos, end_pos, "indentation_flexible"
	end

	-- Strategy 4: Line-trimmed
	start_pos, end_pos = line_trimmed_match(content, old_str)
	if start_pos then
		return start_pos, end_pos, "line_trimmed"
	end

	-- Strategy 5: Fuzzy anchor
	start_pos, end_pos = fuzzy_anchor_match(content, old_str)
	if start_pos then
		return start_pos, end_pos, "fuzzy_anchor"
	end

	return nil, nil, "none"
end

---@param input {path: string, old_string: string, new_string: string}
---@param opts CoderToolOpts
---@return boolean|nil result
---@return string|nil error
function M.func(input, opts)
	if not input.path then
		return nil, "path is required"
	end
	if input.old_string == nil then
		return nil, "old_string is required"
	end
	if input.new_string == nil then
		return nil, "new_string is required"
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Editing file: " .. input.path)
	end

	-- Resolve path
	local path = input.path
	if not vim.startswith(path, "/") then
		path = vim.fn.getcwd() .. "/" .. path
	end

	-- Normalize inputs
	local old_str = normalize_line_endings(input.old_string)
	local new_str = normalize_line_endings(input.new_string)

	-- Handle new file creation (empty old_string)
	if old_str == "" then
		-- Create parent directories
		local dir = vim.fn.fnamemodify(path, ":h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end

		-- Write new file
		local lines = vim.split(new_str, "\n", { plain = true })
		local ok = pcall(vim.fn.writefile, lines, path)

		if not ok then
			return nil, "Failed to create file: " .. input.path
		end

		-- Reload buffer if open
		local bufnr = vim.fn.bufnr(path)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("edit!")
			end)
		end

		if opts.on_complete then
			opts.on_complete(true, nil)
		end

		return true, nil
	end

	-- Check if file exists
	if vim.fn.filereadable(path) ~= 1 then
		return nil, "File not found: " .. input.path
	end

	-- Read current content
	local lines = vim.fn.readfile(path)
	if not lines then
		return nil, "Failed to read file: " .. input.path
	end

	local content = normalize_line_endings(table.concat(lines, "\n"))

	-- Find match using fallback strategies
	local start_pos, end_pos, strategy = find_match(content, old_str)

	if not start_pos then
		return nil, "old_string not found in file (tried 5 matching strategies)"
	end

	if opts.on_log then
		opts.on_log("Match found using strategy: " .. strategy)
	end

	-- Perform replacement
	local new_content = content:sub(1, start_pos - 1) .. new_str .. content:sub(end_pos + 1)

	-- Write back
	local new_lines = vim.split(new_content, "\n", { plain = true })
	local ok = pcall(vim.fn.writefile, new_lines, path)

	if not ok then
		return nil, "Failed to write file: " .. input.path
	end

	-- Reload buffer if open
	local bufnr = vim.fn.bufnr(path)
	if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("edit!")
		end)
	end

	if opts.on_complete then
		opts.on_complete(true, nil)
	end

	return true, nil
end

return M
