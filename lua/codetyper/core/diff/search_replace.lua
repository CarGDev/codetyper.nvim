---@mod codetyper.agent.search_replace Search/Replace editing system
---@brief [[
--- Implements SEARCH/REPLACE block parsing and fuzzy matching for reliable code edits.
--- Parses and applies SEARCH/REPLACE blocks from LLM responses.
--- Uses shared string_match module for matching strategies.
---@brief ]]

local M = {}

local string_match = require("codetyper.support.string_match")
local params = require("codetyper.params.agents.search_replace").patterns

---@class SearchReplaceBlock
---@field search string The text to search for
---@field replace string The text to replace with
---@field file_path string|nil Optional file path for multi-file edits

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
	for search, replace in response:gmatch(params.dash_style) do
		table.insert(blocks, { search = search, replace = replace })
	end

	if #blocks > 0 then
		return blocks
	end

	-- Try claude-style format: <<<<<<< SEARCH ... ======= ... >>>>>>> REPLACE
	for search, replace in response:gmatch(params.claude_style) do
		table.insert(blocks, { search = search, replace = replace })
	end

	if #blocks > 0 then
		return blocks
	end

	-- Try simple format: [SEARCH] ... [REPLACE] ... [END]
	for search, replace in response:gmatch(params.simple_style) do
		table.insert(blocks, { search = search, replace = replace })
	end

	if #blocks > 0 then
		return blocks
	end

	-- Try markdown diff format: ```diff ... ```
	local diff_block = response:match(params.diff_block)
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

	-- Use shared string_match module for line-based matching
	local result = string_match.find_match_lines(content_lines, search_lines)
	if result then
		-- Convert to expected MatchResult format with columns
		return {
			start_line = result.start_line,
			end_line = result.end_line,
			start_col = 1,
			end_col = #content_lines[result.end_line] or 0,
			strategy = result.strategy,
			confidence = result.confidence,
		}
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
	local original_indent = string_match.get_indentation(content_lines[match.start_line])
	local replace_indent = ""
	for _, line in ipairs(replace_lines) do
		if line:match("%S") then
			replace_indent = string_match.get_indentation(line)
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
--- IMPORTANT: Blocks are sorted bottom-to-top to prevent line number invalidation
--- when earlier blocks add/remove lines.
---@param content string Original file content
---@param blocks SearchReplaceBlock[]
---@return string new_content
---@return table results Array of {success: boolean, match: MatchResult|nil, error: string|nil, block_index: number}
function M.apply_blocks(content, blocks)
	-- Step 1: Find all matches first, storing their positions
	local blocks_with_matches = {}
	for i, block in ipairs(blocks) do
		local match = M.find_match(content, block.search)
		if match then
			table.insert(blocks_with_matches, {
				index = i,
				block = block,
				match = match,
			})
		else
			-- Store failed match for results
			table.insert(blocks_with_matches, {
				index = i,
				block = block,
				match = nil,
				error = "Could not find search text in file",
			})
		end
	end

	-- Step 2: Separate successful matches from failures
	local successful = {}
	local failed = {}
	for _, item in ipairs(blocks_with_matches) do
		if item.match then
			table.insert(successful, item)
		else
			table.insert(failed, item)
		end
	end

	-- Step 3: Sort successful matches by start_line DESCENDING (bottom-to-top)
	-- This ensures that applying block N doesn't invalidate line numbers for block N+1
	table.sort(successful, function(a, b)
		return a.match.start_line > b.match.start_line
	end)

	-- Step 4: Apply blocks in sorted order (bottom to top)
	local current_content = content
	local results = {}

	-- Initialize results array with placeholders for original order
	for i = 1, #blocks do
		results[i] = { success = false, error = "not processed", block_index = i }
	end

	-- Apply successful matches
	for _, item in ipairs(successful) do
		local new_content, match, err = M.apply_block(current_content, item.block)
		if new_content then
			current_content = new_content
			results[item.index] = { success = true, match = match, block_index = item.index }
		else
			results[item.index] = { success = false, error = err, block_index = item.index }
		end
	end

	-- Record failed matches
	for _, item in ipairs(failed) do
		results[item.index] = { success = false, error = item.error, block_index = item.index }
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
