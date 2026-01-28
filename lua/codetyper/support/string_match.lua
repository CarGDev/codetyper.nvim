---@mod codetyper.support.string_match String matching utilities
---@brief [[
--- Shared utilities for text matching with multiple fallback strategies.
--- Consolidates duplicate matching code from edit.lua, search_replace.lua, and inline.lua.
---@brief ]]

local M = {}

--- Normalize line endings to LF
---@param str string
---@return string
function M.normalize_line_endings(str)
	return str:gsub("\r\n", "\n"):gsub("\r", "\n")
end

--- Normalize whitespace (collapse multiple spaces to one, trim)
---@param str string
---@return string
function M.normalize_whitespace(str)
	return (str:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", ""))
end

--- Trim trailing whitespace from a string
---@param str string
---@return string
function M.trim_trailing(str)
	return (str:gsub("%s+$", ""))
end

--- Trim both leading and trailing whitespace
---@param str string
---@return string
function M.trim(str)
	return str:match("^%s*(.-)%s*$")
end

--- Get indentation (leading whitespace) of a line
---@param line string
---@return string
function M.get_indentation(line)
	if not line then
		return ""
	end
	return line:match("^(%s*)") or ""
end

--- Strip leading indentation from all lines
---@param str string
---@return string
function M.strip_indentation(str)
	local lines = vim.split(str, "\n")
	local result = {}
	for _, line in ipairs(lines) do
		table.insert(result, line:gsub("^%s+", ""))
	end
	return table.concat(result, "\n")
end

--- Trim each line in a multi-line string
---@param str string
---@return string
function M.trim_lines(str)
	local lines = vim.split(str, "\n")
	local result = {}
	for _, line in ipairs(lines) do
		table.insert(result, M.trim(line))
	end
	return table.concat(result, "\n")
end

--- Calculate Levenshtein distance between two strings
---@param s1 string
---@param s2 string
---@return number
function M.levenshtein(s1, s2)
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
function M.similarity(s1, s2)
	if s1 == s2 then
		return 1.0
	end
	local max_len = math.max(#s1, #s2)
	if max_len == 0 then
		return 1.0
	end
	local distance = M.levenshtein(s1, s2)
	return 1.0 - (distance / max_len)
end

---@class MatchResult
---@field start_pos number Start position in content (character index)
---@field end_pos number End position in content (character index)
---@field start_line? number 1-indexed start line
---@field end_line? number 1-indexed end line
---@field strategy string Name of matching strategy that succeeded
---@field confidence number Match confidence (0.0-1.0)

--- Strategy 1: Exact match
---@param content string File content
---@param old_str string String to find
---@return MatchResult|nil
function M.exact_match(content, old_str)
	local pos = content:find(old_str, 1, true)
	if pos then
		return {
			start_pos = pos,
			end_pos = pos + #old_str - 1,
			strategy = "exact",
			confidence = 1.0,
		}
	end
	return nil
end

--- Strategy 2: Whitespace-normalized match
--- Collapses all whitespace to single spaces
---@param content string
---@param old_str string
---@return MatchResult|nil
function M.whitespace_normalized_match(content, old_str)
	local norm_old = M.normalize_whitespace(old_str)
	local lines = vim.split(content, "\n")

	for i = 1, #lines do
		local block = {}
		for j = i, #lines do
			table.insert(block, lines[j])
			local block_text = table.concat(block, "\n")
			local norm_block = M.normalize_whitespace(block_text)

			if norm_block == norm_old then
				local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
				local start_pos = #before + (i > 1 and 2 or 1)
				local end_pos = start_pos + #block_text - 1
				return {
					start_pos = start_pos,
					end_pos = end_pos,
					start_line = i,
					end_line = j,
					strategy = "whitespace_normalized",
					confidence = 0.95,
				}
			end

			if #norm_block > #norm_old then
				break
			end
		end
	end

	return nil
end

--- Strategy 3: Indentation-flexible match
--- Ignores leading whitespace differences
---@param content string
---@param old_str string
---@return MatchResult|nil
function M.indentation_flexible_match(content, old_str)
	local stripped_old = M.strip_indentation(old_str)
	local lines = vim.split(content, "\n")
	local old_lines = vim.split(old_str, "\n")
	local num_old_lines = #old_lines

	for i = 1, #lines - num_old_lines + 1 do
		local block = vim.list_slice(lines, i, i + num_old_lines - 1)
		local block_text = table.concat(block, "\n")

		if M.strip_indentation(block_text) == stripped_old then
			local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
			local start_pos = #before + (i > 1 and 2 or 1)
			local end_pos = start_pos + #block_text - 1
			return {
				start_pos = start_pos,
				end_pos = end_pos,
				start_line = i,
				end_line = i + num_old_lines - 1,
				strategy = "indentation_flexible",
				confidence = 0.9,
			}
		end
	end

	return nil
end

--- Strategy 4: Line-trimmed match
--- Trims each line before comparing
---@param content string
---@param old_str string
---@return MatchResult|nil
function M.line_trimmed_match(content, old_str)
	local trimmed_old = M.trim_lines(old_str)
	local lines = vim.split(content, "\n")
	local old_lines = vim.split(old_str, "\n")
	local num_old_lines = #old_lines

	for i = 1, #lines - num_old_lines + 1 do
		local block = vim.list_slice(lines, i, i + num_old_lines - 1)
		local block_text = table.concat(block, "\n")

		if M.trim_lines(block_text) == trimmed_old then
			local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
			local start_pos = #before + (i > 1 and 2 or 1)
			local end_pos = start_pos + #block_text - 1
			return {
				start_pos = start_pos,
				end_pos = end_pos,
				start_line = i,
				end_line = i + num_old_lines - 1,
				strategy = "line_trimmed",
				confidence = 0.85,
			}
		end
	end

	return nil
end

--- Strategy 5: Fuzzy anchor-based match
--- Uses first and last lines as anchors, allows fuzzy matching in between
---@param content string
---@param old_str string
---@param threshold? number Similarity threshold (0-1), default 0.8
---@return MatchResult|nil
function M.fuzzy_anchor_match(content, old_str, threshold)
	threshold = threshold or 0.8

	local old_lines = vim.split(old_str, "\n")
	if #old_lines < 2 then
		return nil
	end

	local first_line = M.trim(old_lines[1])
	local last_line = M.trim(old_lines[#old_lines])
	local content_lines = vim.split(content, "\n")

	local candidates = {}
	for i, line in ipairs(content_lines) do
		local trimmed = M.trim(line)
		if
			trimmed == first_line
			or (#first_line > 0 and M.similarity(trimmed, first_line) >= threshold)
		then
			table.insert(candidates, i)
		end
	end

	for _, start_idx in ipairs(candidates) do
		local expected_end = start_idx + #old_lines - 1
		if expected_end <= #content_lines then
			local end_line = M.trim(content_lines[expected_end])
			if
				end_line == last_line
				or (#last_line > 0 and M.similarity(end_line, last_line) >= threshold)
			then
				local total_sim = 0
				for j = 1, #old_lines do
					local c = M.trim(content_lines[start_idx + j - 1])
					local s = M.trim(old_lines[j])
					total_sim = total_sim + M.similarity(c, s)
				end
				local avg_sim = total_sim / #old_lines

				if avg_sim >= 0.7 then
					local before = table.concat(vim.list_slice(content_lines, 1, start_idx - 1), "\n")
					local block = table.concat(vim.list_slice(content_lines, start_idx, expected_end), "\n")
					local start_pos = #before + (start_idx > 1 and 2 or 1)
					local end_pos = start_pos + #block - 1
					return {
						start_pos = start_pos,
						end_pos = end_pos,
						start_line = start_idx,
						end_line = expected_end,
						strategy = "fuzzy_anchor",
						confidence = avg_sim * 0.85,
					}
				end
			end
		end
	end

	return nil
end

--- Try all matching strategies in order of strictness
---@param content string File content
---@param old_str string String to find
---@return MatchResult|nil match
---@return string strategy_name Strategy used ("none" if no match)
function M.find_match(content, old_str)
	local strategies = {
		M.exact_match,
		M.whitespace_normalized_match,
		M.indentation_flexible_match,
		M.line_trimmed_match,
		M.fuzzy_anchor_match,
	}

	for _, strategy in ipairs(strategies) do
		local result = strategy(content, old_str)
		if result then
			return result, result.strategy
		end
	end

	return nil, "none"
end

--- Find match using line-based comparison (for search_replace.lua compatibility)
---@param content_lines string[] Content as array of lines
---@param search_lines string[] Search text as array of lines
---@return MatchResult|nil
function M.find_match_lines(content_lines, search_lines)
	if #search_lines == 0 then
		return nil
	end

	-- Remove trailing empty lines from search
	while #search_lines > 0 and search_lines[#search_lines]:match("^%s*$") do
		table.remove(search_lines)
	end

	if #search_lines == 0 then
		return nil
	end

	-- Try exact line match
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
				start_pos = i,
				end_pos = i + #search_lines - 1,
				start_line = i,
				end_line = i + #search_lines - 1,
				strategy = "exact",
				confidence = 1.0,
			}
		end
	end

	-- Try trimmed match
	local trimmed_search = {}
	for _, line in ipairs(search_lines) do
		table.insert(trimmed_search, M.trim_trailing(line))
	end

	for i = 1, #content_lines - #search_lines + 1 do
		local match = true
		for j = 1, #search_lines do
			if M.trim_trailing(content_lines[i + j - 1]) ~= trimmed_search[j] then
				match = false
				break
			end
		end
		if match then
			return {
				start_pos = i,
				end_pos = i + #search_lines - 1,
				start_line = i,
				end_line = i + #search_lines - 1,
				strategy = "line_trimmed",
				confidence = 0.95,
			}
		end
	end

	-- Try fuzzy anchor match
	if #search_lines >= 2 then
		local first_search = M.trim_trailing(search_lines[1])
		local last_search = M.trim_trailing(search_lines[#search_lines])

		for i = 1, #content_lines - #search_lines + 1 do
			local first_content = M.trim_trailing(content_lines[i])
			if M.similarity(first_content, first_search) > 0.8 then
				local last_idx = i + #search_lines - 1
				if last_idx <= #content_lines then
					local last_content = M.trim_trailing(content_lines[last_idx])
					if M.similarity(last_content, last_search) > 0.8 then
						local total_sim = 0
						for j = 1, #search_lines do
							local c = M.trim_trailing(content_lines[i + j - 1])
							local s = M.trim_trailing(search_lines[j])
							total_sim = total_sim + M.similarity(c, s)
						end
						local avg_sim = total_sim / #search_lines
						if avg_sim > 0.7 then
							return {
								start_pos = i,
								end_pos = i + #search_lines - 1,
								start_line = i,
								end_line = i + #search_lines - 1,
								strategy = "block_anchor",
								confidence = avg_sim * 0.85,
							}
						end
					end
				end
			end
		end
	end

	return nil
end

return M
