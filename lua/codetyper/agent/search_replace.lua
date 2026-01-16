---@mod codetyper.agent.search_replace Search/Replace editing system
---@brief [[
--- Implements SEARCH/REPLACE block parsing and fuzzy matching for reliable code edits.
--- Parses and applies SEARCH/REPLACE blocks from LLM responses.
---@brief ]]

local M = {}

---@class SearchReplaceBlock
---@field search string The text to search for
---@field replace string The text to replace with
---@field file_path string|nil Optional file path for multi-file edits

---@class MatchResult
---@field start_line number 1-indexed start line
---@field end_line number 1-indexed end line
---@field start_col number 1-indexed start column (for partial line matches)
---@field end_col number 1-indexed end column
---@field strategy string Which matching strategy succeeded
---@field confidence number Match confidence (0.0-1.0)

--- Parse SEARCH/REPLACE blocks from LLM response
--- Supports multiple formats:
--- Format 1 (dash style):
---   ------- SEARCH
---   old code
---   =======
---   new code
---   +++++++ REPLACE
---
--- Format 2 (claude style):
---   <<<<<<< SEARCH
---   old code
---   =======
---   new code
---   >>>>>>> REPLACE
---
--- Format 3 (simple):
---   [SEARCH]
---   old code
---   [REPLACE]
---   new code
---   [END]
---
---@param response string LLM response text
---@return SearchReplaceBlock[]
function M.parse_blocks(response)
	local blocks = {}

	-- Try dash-style format: ------- SEARCH ... ======= ... +++++++ REPLACE
	for search, replace in response:gmatch("%-%-%-%-%-%-%-?%s*SEARCH%s*\n(.-)\n=======%s*\n(.-)\n%+%+%+%+%+%+%+?%s*REPLACE") do
		table.insert(blocks, { search = search, replace = replace })
	end

	if #blocks > 0 then
		return blocks
	end

	-- Try claude-style format: <<<<<<< SEARCH ... ======= ... >>>>>>> REPLACE
	for search, replace in response:gmatch("<<<<<<<[%s]*SEARCH%s*\n(.-)\n=======%s*\n(.-)\n>>>>>>>[%s]*REPLACE") do
		table.insert(blocks, { search = search, replace = replace })
	end

	if #blocks > 0 then
		return blocks
	end

	-- Try simple format: [SEARCH] ... [REPLACE] ... [END]
	for search, replace in response:gmatch("%[SEARCH%]%s*\n(.-)\n%[REPLACE%]%s*\n(.-)\n%[END%]") do
		table.insert(blocks, { search = search, replace = replace })
	end

	if #blocks > 0 then
		return blocks
	end

	-- Try markdown diff format: ```diff ... ```
	local diff_block = response:match("```diff\n(.-)\n```")
	if diff_block then
		local old_lines = {}
		local new_lines = {}
		for line in diff_block:gmatch("[^\n]+") do
			if line:match("^%-[^%-]") then
				-- Removed line (starts with single -)
				table.insert(old_lines, line:sub(2))
			elseif line:match("^%+[^%+]") then
				-- Added line (starts with single +)
				table.insert(new_lines, line:sub(2))
			elseif line:match("^%s") or line:match("^[^%-%+@]") then
				-- Context line
				table.insert(old_lines, line:match("^%s?(.*)"))
				table.insert(new_lines, line:match("^%s?(.*)"))
			end
		end
		if #old_lines > 0 or #new_lines > 0 then
			table.insert(blocks, {
				search = table.concat(old_lines, "\n"),
				replace = table.concat(new_lines, "\n"),
			})
		end
	end

	return blocks
end

--- Get indentation of a line
---@param line string
---@return string
local function get_indentation(line)
	if not line then
		return ""
	end
	return line:match("^(%s*)") or ""
end

--- Normalize whitespace in a string (collapse multiple spaces to one)
---@param str string
---@return string
local function normalize_whitespace(str)
	-- Wrap in parentheses to only return first value (gsub returns string + count)
	return (str:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", ""))
end

--- Trim trailing whitespace from each line
---@param str string
---@return string
local function trim_lines(str)
	local lines = vim.split(str, "\n", { plain = true })
	for i, line in ipairs(lines) do
		-- Wrap in parentheses to only get string, not count
		lines[i] = (line:gsub("%s+$", ""))
	end
	return table.concat(lines, "\n")
end

--- Calculate Levenshtein distance between two strings
---@param s1 string
---@param s2 string
---@return number
local function levenshtein(s1, s2)
	local len1, len2 = #s1, #s2
	if len1 == 0 then
		return len2
	end
	if len2 == 0 then
		return len1
	end

	local matrix = {}
	for i = 0, len1 do
		matrix[i] = { [0] = i }
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	for i = 1, len1 do
		for j = 1, len2 do
			local cost = (s1:sub(i, i) == s2:sub(j, j)) and 0 or 1
			matrix[i][j] = math.min(
				matrix[i - 1][j] + 1,
				matrix[i][j - 1] + 1,
				matrix[i - 1][j - 1] + cost
			)
		end
	end

	return matrix[len1][len2]
end

--- Calculate similarity ratio (0.0-1.0) between two strings
---@param s1 string
---@param s2 string
---@return number
local function similarity(s1, s2)
	if s1 == s2 then
		return 1.0
	end
	local max_len = math.max(#s1, #s2)
	if max_len == 0 then
		return 1.0
	end
	local distance = levenshtein(s1, s2)
	return 1.0 - (distance / max_len)
end

--- Strategy 1: Exact match
---@param content_lines string[]
---@param search_lines string[]
---@return MatchResult|nil
local function exact_match(content_lines, search_lines)
	if #search_lines == 0 then
		return nil
	end

	for i = 1, #content_lines - #search_lines + 1 do
		local match = true
		for j = 1, #search_lines do
			if content_lines[i + j - 1] ~= search_lines[j] then
				match = false
				break
			end
		end
		if match then
			return {
				start_line = i,
				end_line = i + #search_lines - 1,
				start_col = 1,
				end_col = #content_lines[i + #search_lines - 1],
				strategy = "exact",
				confidence = 1.0,
			}
		end
	end

	return nil
end

--- Strategy 2: Line-trimmed match (ignore trailing whitespace)
---@param content_lines string[]
---@param search_lines string[]
---@return MatchResult|nil
local function line_trimmed_match(content_lines, search_lines)
	if #search_lines == 0 then
		return nil
	end

	local trimmed_search = {}
	for _, line in ipairs(search_lines) do
		table.insert(trimmed_search, (line:gsub("%s+$", "")))
	end

	for i = 1, #content_lines - #search_lines + 1 do
		local match = true
		for j = 1, #search_lines do
			local trimmed_content = content_lines[i + j - 1]:gsub("%s+$", "")
			if trimmed_content ~= trimmed_search[j] then
				match = false
				break
			end
		end
		if match then
			return {
				start_line = i,
				end_line = i + #search_lines - 1,
				start_col = 1,
				end_col = #content_lines[i + #search_lines - 1],
				strategy = "line_trimmed",
				confidence = 0.95,
			}
		end
	end

	return nil
end

--- Strategy 3: Indentation-flexible match (normalize indentation)
---@param content_lines string[]
---@param search_lines string[]
---@return MatchResult|nil
local function indentation_flexible_match(content_lines, search_lines)
	if #search_lines == 0 then
		return nil
	end

	-- Get base indentation from search (first non-empty line)
	local search_indent = ""
	for _, line in ipairs(search_lines) do
		if line:match("%S") then
			search_indent = get_indentation(line)
			break
		end
	end

	-- Strip common indentation from search
	local stripped_search = {}
	for _, line in ipairs(search_lines) do
		if line:match("^" .. vim.pesc(search_indent)) then
			table.insert(stripped_search, line:sub(#search_indent + 1))
		else
			table.insert(stripped_search, line)
		end
	end

	for i = 1, #content_lines - #search_lines + 1 do
		-- Get content indentation at this position
		local content_indent = ""
		for j = 0, #search_lines - 1 do
			local line = content_lines[i + j]
			if line:match("%S") then
				content_indent = get_indentation(line)
				break
			end
		end

		local match = true
		for j = 1, #search_lines do
			local content_line = content_lines[i + j - 1]
			local expected = content_indent .. stripped_search[j]

			-- Compare with normalized indentation
			if content_line:gsub("%s+$", "") ~= expected:gsub("%s+$", "") then
				match = false
				break
			end
		end

		if match then
			return {
				start_line = i,
				end_line = i + #search_lines - 1,
				start_col = 1,
				end_col = #content_lines[i + #search_lines - 1],
				strategy = "indentation_flexible",
				confidence = 0.9,
			}
		end
	end

	return nil
end

--- Strategy 4: Block anchor match (match first/last lines, fuzzy middle)
---@param content_lines string[]
---@param search_lines string[]
---@return MatchResult|nil
local function block_anchor_match(content_lines, search_lines)
	if #search_lines < 2 then
		return nil
	end

	local first_search = search_lines[1]:gsub("%s+$", "")
	local last_search = search_lines[#search_lines]:gsub("%s+$", "")

	-- Find potential start positions
	local candidates = {}
	for i = 1, #content_lines - #search_lines + 1 do
		local first_content = content_lines[i]:gsub("%s+$", "")
		if similarity(first_content, first_search) > 0.8 then
			-- Check if last line also matches
			local last_idx = i + #search_lines - 1
			if last_idx <= #content_lines then
				local last_content = content_lines[last_idx]:gsub("%s+$", "")
				if similarity(last_content, last_search) > 0.8 then
					-- Calculate overall similarity
					local total_sim = 0
					for j = 1, #search_lines do
						local c = content_lines[i + j - 1]:gsub("%s+$", "")
						local s = search_lines[j]:gsub("%s+$", "")
						total_sim = total_sim + similarity(c, s)
					end
					local avg_sim = total_sim / #search_lines
					if avg_sim > 0.7 then
						table.insert(candidates, { start = i, similarity = avg_sim })
					end
				end
			end
		end
	end

	-- Return best match
	if #candidates > 0 then
		table.sort(candidates, function(a, b)
			return a.similarity > b.similarity
		end)
		local best = candidates[1]
		return {
			start_line = best.start,
			end_line = best.start + #search_lines - 1,
			start_col = 1,
			end_col = #content_lines[best.start + #search_lines - 1],
			strategy = "block_anchor",
			confidence = best.similarity * 0.85,
		}
	end

	return nil
end

--- Strategy 5: Whitespace-normalized match
---@param content_lines string[]
---@param search_lines string[]
---@return MatchResult|nil
local function whitespace_normalized_match(content_lines, search_lines)
	if #search_lines == 0 then
		return nil
	end

	-- Normalize search lines
	local norm_search = {}
	for _, line in ipairs(search_lines) do
		table.insert(norm_search, normalize_whitespace(line))
	end

	for i = 1, #content_lines - #search_lines + 1 do
		local match = true
		for j = 1, #search_lines do
			local norm_content = normalize_whitespace(content_lines[i + j - 1])
			if norm_content ~= norm_search[j] then
				match = false
				break
			end
		end
		if match then
			return {
				start_line = i,
				end_line = i + #search_lines - 1,
				start_col = 1,
				end_col = #content_lines[i + #search_lines - 1],
				strategy = "whitespace_normalized",
				confidence = 0.8,
			}
		end
	end

	return nil
end

--- Find the best match for search text in content
---@param content string File content
---@param search string Text to search for
---@return MatchResult|nil
function M.find_match(content, search)
	local content_lines = vim.split(content, "\n", { plain = true })
	local search_lines = vim.split(search, "\n", { plain = true })

	-- Remove trailing empty lines from search
	while #search_lines > 0 and search_lines[#search_lines]:match("^%s*$") do
		table.remove(search_lines)
	end

	if #search_lines == 0 then
		return nil
	end

	-- Try strategies in order of strictness
	local strategies = {
		exact_match,
		line_trimmed_match,
		indentation_flexible_match,
		block_anchor_match,
		whitespace_normalized_match,
	}

	for _, strategy in ipairs(strategies) do
		local result = strategy(content_lines, search_lines)
		if result then
			return result
		end
	end

	return nil
end

--- Apply a single SEARCH/REPLACE block to content
---@param content string Original file content
---@param block SearchReplaceBlock
---@return string|nil new_content
---@return MatchResult|nil match_info
---@return string|nil error
function M.apply_block(content, block)
	local match = M.find_match(content, block.search)
	if not match then
		return nil, nil, "Could not find search text in file"
	end

	local content_lines = vim.split(content, "\n", { plain = true })
	local replace_lines = vim.split(block.replace, "\n", { plain = true })

	-- Adjust indentation of replacement to match original
	local original_indent = get_indentation(content_lines[match.start_line])
	local replace_indent = ""
	for _, line in ipairs(replace_lines) do
		if line:match("%S") then
			replace_indent = get_indentation(line)
			break
		end
	end

	-- Apply indentation adjustment
	local adjusted_replace = {}
	for _, line in ipairs(replace_lines) do
		if line:match("^" .. vim.pesc(replace_indent)) then
			table.insert(adjusted_replace, original_indent .. line:sub(#replace_indent + 1))
		elseif line:match("^%s*$") then
			table.insert(adjusted_replace, "")
		else
			table.insert(adjusted_replace, original_indent .. line)
		end
	end

	-- Build new content
	local new_lines = {}
	for i = 1, match.start_line - 1 do
		table.insert(new_lines, content_lines[i])
	end
	for _, line in ipairs(adjusted_replace) do
		table.insert(new_lines, line)
	end
	for i = match.end_line + 1, #content_lines do
		table.insert(new_lines, content_lines[i])
	end

	return table.concat(new_lines, "\n"), match, nil
end

--- Apply multiple SEARCH/REPLACE blocks to content
---@param content string Original file content
---@param blocks SearchReplaceBlock[]
---@return string new_content
---@return table results Array of {success: boolean, match: MatchResult|nil, error: string|nil}
function M.apply_blocks(content, blocks)
	local current_content = content
	local results = {}

	for _, block in ipairs(blocks) do
		local new_content, match, err = M.apply_block(current_content, block)
		if new_content then
			current_content = new_content
			table.insert(results, { success = true, match = match })
		else
			table.insert(results, { success = false, error = err })
		end
	end

	return current_content, results
end

--- Apply SEARCH/REPLACE blocks to a buffer
---@param bufnr number Buffer number
---@param blocks SearchReplaceBlock[]
---@return boolean success
---@return string|nil error
function M.apply_to_buffer(bufnr, blocks)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false, "Invalid buffer"
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local new_content, results = M.apply_blocks(content, blocks)

	-- Check for any failures
	local failures = {}
	for i, result in ipairs(results) do
		if not result.success then
			table.insert(failures, string.format("Block %d: %s", i, result.error or "unknown error"))
		end
	end

	if #failures > 0 then
		return false, table.concat(failures, "; ")
	end

	-- Apply to buffer
	local new_lines = vim.split(new_content, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

	return true, nil
end

--- Check if response contains SEARCH/REPLACE blocks
---@param response string
---@return boolean
function M.has_blocks(response)
	return #M.parse_blocks(response) > 0
end

return M
