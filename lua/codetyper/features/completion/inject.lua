---@mod codetyper.agent.inject Smart code injection with import handling
---@brief [[
--- Intelligent code injection that properly handles imports, merging them
--- into existing import sections instead of blindly appending.
---@brief ]]

local M = {}

---@class ImportConfig
---@field pattern string Lua pattern to match import statements
---@field multi_line boolean Whether imports can span multiple lines
---@field sort_key function|nil Function to extract sort key from import
---@field group_by function|nil Function to group imports

---@class ParsedCode
---@field imports string[] Import statements
---@field body string[] Non-import code lines
---@field import_lines table<number, boolean> Map of line numbers that are imports

local utils = require("codetyper.support.utils")
local languages = require("codetyper.params.agent.languages")
local import_patterns = languages.import_patterns

--- Check if a line is an import statement for the given language
---@param line string
---@param patterns table[] Import patterns for the language
---@return boolean is_import
---@return boolean is_multi_line
local function is_import_line(line, patterns)
	for _, p in ipairs(patterns) do
		if line:match(p.pattern) then
			return true, p.multi_line or false
		end
	end
	return false, false
end


--- Check if a line ends a multi-line import
---@param line string
---@param filetype string
---@return boolean
local function ends_multiline_import(line, filetype)
	return utils.ends_multiline_import(line, filetype)
end

--- Parse code into imports and body
---@param code string|string[] Code to parse
---@param filetype string File type/extension
---@return ParsedCode
function M.parse_code(code, filetype)
	local lines
	if type(code) == "string" then
		lines = vim.split(code, "\n", { plain = true })
	else
		lines = code
	end

	local patterns = import_patterns[filetype] or import_patterns.javascript

	local result = {
		imports = {},
		body = {},
		import_lines = {},
	}

	local in_multiline_import = false
	local current_import_lines = {}

	for i, line in ipairs(lines) do
		if in_multiline_import then
			-- Continue collecting multi-line import
			table.insert(current_import_lines, line)

			if ends_multiline_import(line, filetype) then
				-- Complete the multi-line import
				table.insert(result.imports, table.concat(current_import_lines, "\n"))
				for j = i - #current_import_lines + 1, i do
					result.import_lines[j] = true
				end
				current_import_lines = {}
				in_multiline_import = false
			end
		else
			local is_import, is_multi = is_import_line(line, patterns)

			if is_import then
				result.import_lines[i] = true

				if is_multi and not ends_multiline_import(line, filetype) then
					-- Start of multi-line import
					in_multiline_import = true
					current_import_lines = { line }
				else
					-- Single-line import
					table.insert(result.imports, line)
				end
			else
				-- Non-import line
				table.insert(result.body, line)
			end
		end
	end

	-- Handle unclosed multi-line import (shouldn't happen with well-formed code)
	if #current_import_lines > 0 then
		table.insert(result.imports, table.concat(current_import_lines, "\n"))
	end

	return result
end

--- Find the import section range in a buffer
---@param bufnr number Buffer number
---@param filetype string
---@return number|nil start_line First import line (1-indexed)
---@return number|nil end_line Last import line (1-indexed)
function M.find_import_section(bufnr, filetype)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local patterns = import_patterns[filetype] or import_patterns.javascript

	local first_import = nil
	local last_import = nil
	local in_multiline = false
	local consecutive_non_import = 0
	local max_gap = 3 -- Allow up to 3 blank/comment lines between imports

	for i, line in ipairs(lines) do
		if in_multiline then
			last_import = i
			consecutive_non_import = 0

			if ends_multiline_import(line, filetype) then
				in_multiline = false
			end
		else
			local is_import, is_multi = is_import_line(line, patterns)

			if is_import then
				if not first_import then
					first_import = i
				end
				last_import = i
				consecutive_non_import = 0

				if is_multi and not ends_multiline_import(line, filetype) then
					in_multiline = true
				end
			elseif utils.is_empty_or_comment(line, filetype) then
				-- Allow gaps in import section
				if first_import then
					consecutive_non_import = consecutive_non_import + 1
					if consecutive_non_import > max_gap then
						-- Too many non-import lines, import section has ended
						break
					end
				end
			else
				-- Non-import, non-empty line
				if first_import then
					-- Import section has ended
					break
				end
			end
		end
	end

	return first_import, last_import
end

--- Get existing imports from a buffer
---@param bufnr number Buffer number
---@param filetype string
---@return string[] Existing import statements
function M.get_existing_imports(bufnr, filetype)
	local start_line, end_line = M.find_import_section(bufnr, filetype)
	if not start_line then
		return {}
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	local parsed = M.parse_code(lines, filetype)
	return parsed.imports
end

--- Normalize an import for comparison (remove whitespace variations)
---@param import_str string
---@return string
local function normalize_import(import_str)
	-- Remove trailing semicolon for comparison
	local normalized = import_str:gsub(";%s*$", "")
	-- Remove all whitespace around braces, commas, colons
	normalized = normalized:gsub("%s*{%s*", "{")
	normalized = normalized:gsub("%s*}%s*", "}")
	normalized = normalized:gsub("%s*,%s*", ",")
	normalized = normalized:gsub("%s*:%s*", ":")
	-- Collapse multiple whitespace to single space
	normalized = normalized:gsub("%s+", " ")
	-- Trim leading/trailing whitespace
	normalized = normalized:match("^%s*(.-)%s*$")
	return normalized
end

--- Check if two imports are duplicates
---@param import1 string
---@param import2 string
---@return boolean
local function are_duplicate_imports(import1, import2)
	return normalize_import(import1) == normalize_import(import2)
end

--- Merge new imports with existing ones, avoiding duplicates
---@param existing string[] Existing imports
---@param new_imports string[] New imports to merge
---@return string[] Merged imports
function M.merge_imports(existing, new_imports)
	local merged = {}
	local seen = {}

	-- Add existing imports
	for _, imp in ipairs(existing) do
		local normalized = normalize_import(imp)
		if not seen[normalized] then
			seen[normalized] = true
			table.insert(merged, imp)
		end
	end

	-- Add new imports that aren't duplicates
	for _, imp in ipairs(new_imports) do
		local normalized = normalize_import(imp)
		if not seen[normalized] then
			seen[normalized] = true
			table.insert(merged, imp)
		end
	end

	return merged
end

--- Sort imports by their source/module
---@param imports string[]
---@param filetype string
---@return string[]
function M.sort_imports(imports, filetype)
	-- Group imports: stdlib/builtin first, then third-party, then local
	local builtin = {}
	local third_party = {}
	local local_imports = {}

	for _, imp in ipairs(imports) do
		local category = utils.classify_import(imp, filetype)

		if category == "builtin" then
			table.insert(builtin, imp)
		elseif category == "local" then
			table.insert(local_imports, imp)
		else
			table.insert(third_party, imp)
		end
	end

	-- Sort each group alphabetically
	table.sort(builtin)
	table.sort(third_party)
	table.sort(local_imports)

	-- Combine with proper spacing
	local result = {}

	for _, imp in ipairs(builtin) do
		table.insert(result, imp)
	end
	if #builtin > 0 and (#third_party > 0 or #local_imports > 0) then
		table.insert(result, "") -- Blank line between groups
	end

	for _, imp in ipairs(third_party) do
		table.insert(result, imp)
	end
	if #third_party > 0 and #local_imports > 0 then
		table.insert(result, "") -- Blank line between groups
	end

	for _, imp in ipairs(local_imports) do
		table.insert(result, imp)
	end

	return result
end

---@class InjectResult
---@field success boolean
---@field imports_added number Number of new imports added
---@field imports_merged boolean Whether imports were merged into existing section
---@field body_lines number Number of body lines injected

--- Smart inject code into a buffer, properly handling imports
---@param bufnr number Target buffer
---@param code string|string[] Code to inject
---@param opts table Options: { strategy: "append"|"replace"|"insert", range: {start_line, end_line}|nil, filetype: string|nil, sort_imports: boolean|nil }
---@return InjectResult
function M.inject(bufnr, code, opts)
	opts = opts or {}

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return { success = false, imports_added = 0, imports_merged = false, body_lines = 0 }
	end

	-- Get filetype
	local filetype = opts.filetype
	if not filetype then
		local bufname = vim.api.nvim_buf_get_name(bufnr)
		filetype = vim.fn.fnamemodify(bufname, ":e")
	end

	-- Parse the code to separate imports from body
	local parsed = M.parse_code(code, filetype)

	local result = {
		success = true,
		imports_added = 0,
		imports_merged = false,
		body_lines = #parsed.body,
	}

	-- Handle imports first if there are any
	if #parsed.imports > 0 then
		local import_start, import_end = M.find_import_section(bufnr, filetype)

		if import_start then
			-- Merge with existing import section
			local existing_imports = M.get_existing_imports(bufnr, filetype)
			local merged = M.merge_imports(existing_imports, parsed.imports)

			-- Count how many new imports were actually added
			result.imports_added = #merged - #existing_imports
			result.imports_merged = true

			-- Optionally sort imports
			if opts.sort_imports ~= false then
				merged = M.sort_imports(merged, filetype)
			end

			-- Convert back to lines (handling multi-line imports)
			local import_lines = {}
			for _, imp in ipairs(merged) do
				for _, line in ipairs(vim.split(imp, "\n", { plain = true })) do
					table.insert(import_lines, line)
				end
			end

			-- Replace the import section
			vim.api.nvim_buf_set_lines(bufnr, import_start - 1, import_end, false, import_lines)

			-- Adjust line numbers for body injection
			local lines_diff = #import_lines - (import_end - import_start + 1)
			if opts.range and opts.range.start_line and opts.range.start_line > import_end then
				opts.range.start_line = opts.range.start_line + lines_diff
				if opts.range.end_line then
					opts.range.end_line = opts.range.end_line + lines_diff
				end
			end
		else
			-- No existing import section, add imports at the top
			-- Find the first non-comment, non-empty line
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local insert_at = 0

			for i, line in ipairs(lines) do
				local trimmed = line:match("^%s*(.-)%s*$")
				-- Skip shebang, docstrings, and initial comments
				if trimmed ~= "" and not trimmed:match("^#!")
					and not trimmed:match("^['\"]") and not utils.is_empty_or_comment(line, filetype) then
					insert_at = i - 1
					break
				end
				insert_at = i
			end

			-- Add imports with a trailing blank line
			local import_lines = {}
			for _, imp in ipairs(parsed.imports) do
				for _, line in ipairs(vim.split(imp, "\n", { plain = true })) do
					table.insert(import_lines, line)
				end
			end
			table.insert(import_lines, "") -- Blank line after imports

			vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, import_lines)
			result.imports_added = #parsed.imports
			result.imports_merged = false

			-- Adjust body injection range
			if opts.range and opts.range.start_line then
				opts.range.start_line = opts.range.start_line + #import_lines
				if opts.range.end_line then
					opts.range.end_line = opts.range.end_line + #import_lines
				end
			end
		end
	end

	-- Handle body (non-import) code
	if #parsed.body > 0 then
		-- Filter out empty leading/trailing lines from body
		local body_lines = parsed.body
		while #body_lines > 0 and body_lines[1]:match("^%s*$") do
			table.remove(body_lines, 1)
		end
		while #body_lines > 0 and body_lines[#body_lines]:match("^%s*$") do
			table.remove(body_lines)
		end

		if #body_lines > 0 then
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			local strategy = opts.strategy or "append"

			if strategy == "replace" and opts.range then
				local start_line = math.max(1, opts.range.start_line)
				local end_line = math.min(line_count, opts.range.end_line)
				vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, body_lines)
			elseif strategy == "insert" and opts.range then
				local insert_line = math.max(0, math.min(line_count, opts.range.start_line - 1))
				vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, body_lines)
			else
				-- Default: append
				local last_line = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""
				if last_line:match("%S") then
					-- Add blank line for spacing
					table.insert(body_lines, 1, "")
				end
				vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, body_lines)
			end

			result.body_lines = #body_lines
		end
	end

	return result
end

--- Check if code contains imports
---@param code string|string[]
---@param filetype string
---@return boolean
function M.has_imports(code, filetype)
	local parsed = M.parse_code(code, filetype)
	return #parsed.imports > 0
end

return M
