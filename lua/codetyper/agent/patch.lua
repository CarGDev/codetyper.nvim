---@mod codetyper.agent.patch Patch system with staleness detection
---@brief [[
--- Manages code patches with buffer snapshots for staleness detection.
--- Patches are queued for safe injection when completion popup is not visible.
---@brief ]]

local M = {}

---@class BufferSnapshot
---@field bufnr number Buffer number
---@field changedtick number vim.b.changedtick at snapshot time
---@field content_hash string Hash of buffer content in range
---@field range {start_line: number, end_line: number}|nil Range snapshotted

---@class PatchCandidate
---@field id string Unique patch ID
---@field event_id string Related PromptEvent ID
---@field target_bufnr number Target buffer for injection
---@field target_path string Target file path
---@field original_snapshot BufferSnapshot Snapshot at event creation
---@field generated_code string Code to inject
---@field injection_range {start_line: number, end_line: number}|nil
---@field injection_strategy string "append"|"replace"|"insert"
---@field confidence number Confidence score (0.0-1.0)
---@field status string "pending"|"applied"|"stale"|"rejected"
---@field created_at number Timestamp
---@field applied_at number|nil When applied

--- Patch storage
---@type PatchCandidate[]
local patches = {}

--- Patch ID counter
local patch_counter = 0

--- Generate unique patch ID
---@return string
function M.generate_id()
	patch_counter = patch_counter + 1
	return string.format("patch_%d_%d", os.time(), patch_counter)
end

--- Hash buffer content in range
---@param bufnr number
---@param start_line number|nil 1-indexed, nil for whole buffer
---@param end_line number|nil 1-indexed, nil for whole buffer
---@return string
local function hash_buffer_range(bufnr, start_line, end_line)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return ""
	end

	local lines
	if start_line and end_line then
		lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	else
		lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end

	local content = table.concat(lines, "\n")
	local hash = 0
	for i = 1, #content do
		hash = (hash * 31 + string.byte(content, i)) % 2147483647
	end
	return string.format("%x", hash)
end

--- Take a snapshot of buffer state
---@param bufnr number Buffer number
---@param range {start_line: number, end_line: number}|nil Optional range
---@return BufferSnapshot
function M.snapshot_buffer(bufnr, range)
	local changedtick = 0
	if vim.api.nvim_buf_is_valid(bufnr) then
		changedtick = vim.api.nvim_buf_get_var(bufnr, "changedtick") or vim.b[bufnr].changedtick or 0
	end

	local content_hash
	if range then
		content_hash = hash_buffer_range(bufnr, range.start_line, range.end_line)
	else
		content_hash = hash_buffer_range(bufnr, nil, nil)
	end

	return {
		bufnr = bufnr,
		changedtick = changedtick,
		content_hash = content_hash,
		range = range,
	}
end

--- Check if buffer changed since snapshot
---@param snapshot BufferSnapshot
---@return boolean is_stale
---@return string|nil reason
function M.is_snapshot_stale(snapshot)
	if not vim.api.nvim_buf_is_valid(snapshot.bufnr) then
		return true, "buffer_invalid"
	end

	-- Check changedtick first (fast path)
	local current_tick = vim.api.nvim_buf_get_var(snapshot.bufnr, "changedtick")
		or vim.b[snapshot.bufnr].changedtick or 0

	if current_tick ~= snapshot.changedtick then
		-- Changedtick differs, but might be just cursor movement
		-- Verify with content hash
		local current_hash
		if snapshot.range then
			current_hash = hash_buffer_range(
				snapshot.bufnr,
				snapshot.range.start_line,
				snapshot.range.end_line
			)
		else
			current_hash = hash_buffer_range(snapshot.bufnr, nil, nil)
		end

		if current_hash ~= snapshot.content_hash then
			return true, "content_changed"
		end
	end

	return false, nil
end

--- Check if a patch is stale
---@param patch PatchCandidate
---@return boolean
---@return string|nil reason
function M.is_stale(patch)
	return M.is_snapshot_stale(patch.original_snapshot)
end

--- Queue a patch for deferred application
---@param patch PatchCandidate
---@return PatchCandidate
function M.queue_patch(patch)
	patch.id = patch.id or M.generate_id()
	patch.status = patch.status or "pending"
	patch.created_at = patch.created_at or os.time()

	table.insert(patches, patch)

	-- Log patch creation
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "patch",
			message = string.format(
				"Patch queued: %s (confidence: %.2f)",
				patch.id, patch.confidence or 0
			),
			data = {
				patch_id = patch.id,
				event_id = patch.event_id,
				target_path = patch.target_path,
				code_preview = patch.generated_code:sub(1, 50),
			},
		})
	end)

	return patch
end

--- Create patch from event and response
---@param event table PromptEvent
---@param generated_code string
---@param confidence number
---@param strategy string|nil Injection strategy (overrides intent-based)
---@return PatchCandidate
function M.create_from_event(event, generated_code, confidence, strategy)
	-- Get target buffer
	local target_bufnr = vim.fn.bufnr(event.target_path)
	if target_bufnr == -1 then
		-- Try to find by filename
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(buf)
			if name == event.target_path then
				target_bufnr = buf
				break
			end
		end
	end

	-- Take snapshot of the scope range in target buffer (for staleness detection)
	local snapshot_range = event.scope_range or event.range
	local snapshot = M.snapshot_buffer(
		target_bufnr ~= -1 and target_bufnr or event.bufnr,
		snapshot_range
	)

	-- Determine injection strategy and range based on intent
	local injection_strategy = strategy
	local injection_range = nil

	if not injection_strategy and event.intent then
		local intent_mod = require("codetyper.agent.intent")
		if intent_mod.is_replacement(event.intent) then
			injection_strategy = "replace"
			-- Use scope range for replacement
			if event.scope_range then
				injection_range = event.scope_range
			end
		elseif event.intent.action == "insert" then
			injection_strategy = "insert"
			-- Insert at prompt location
			injection_range = { start_line = event.range.start_line, end_line = event.range.start_line }
		elseif event.intent.action == "append" then
			injection_strategy = "append"
			-- Will append to end of file
		else
			injection_strategy = "append"
		end
	end

	injection_strategy = injection_strategy or "append"

	return {
		id = M.generate_id(),
		event_id = event.id,
		target_bufnr = target_bufnr,
		target_path = event.target_path,
		original_snapshot = snapshot,
		generated_code = generated_code,
		injection_range = injection_range,
		injection_strategy = injection_strategy,
		confidence = confidence,
		status = "pending",
		created_at = os.time(),
		intent = event.intent,
		scope = event.scope,
		-- Store the prompt tag range so we can delete it after applying
		prompt_tag_range = event.range,
	}
end

--- Get all pending patches
---@return PatchCandidate[]
function M.get_pending()
	local pending = {}
	for _, patch in ipairs(patches) do
		if patch.status == "pending" then
			table.insert(pending, patch)
		end
	end
	return pending
end

--- Get patch by ID
---@param id string
---@return PatchCandidate|nil
function M.get(id)
	for _, patch in ipairs(patches) do
		if patch.id == id then
			return patch
		end
	end
	return nil
end

--- Get patches for event
---@param event_id string
---@return PatchCandidate[]
function M.get_for_event(event_id)
	local result = {}
	for _, patch in ipairs(patches) do
		if patch.event_id == event_id then
			table.insert(result, patch)
		end
	end
	return result
end

--- Mark patch as applied
---@param id string
---@return boolean
function M.mark_applied(id)
	local patch = M.get(id)
	if patch then
		patch.status = "applied"
		patch.applied_at = os.time()
		return true
	end
	return false
end

--- Mark patch as stale
---@param id string
---@param reason string|nil
---@return boolean
function M.mark_stale(id, reason)
	local patch = M.get(id)
	if patch then
		patch.status = "stale"
		patch.stale_reason = reason
		return true
	end
	return false
end

--- Mark patch as rejected
---@param id string
---@param reason string|nil
---@return boolean
function M.mark_rejected(id, reason)
	local patch = M.get(id)
	if patch then
		patch.status = "rejected"
		patch.reject_reason = reason
		return true
	end
	return false
end

--- Remove /@ @/ prompt tags from buffer
---@param bufnr number Buffer number
---@return number Number of tag regions removed
local function remove_prompt_tags(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return 0
	end

	local removed = 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Find and remove all /@ ... @/ regions (can be multiline)
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local open_start = line:find("/@")

		if open_start then
			-- Found an opening tag, look for closing tag
			local close_end = nil
			local close_line = i

			-- Check if closing tag is on same line
			local after_open = line:sub(open_start + 2)
			local same_line_close = after_open:find("@/")
			if same_line_close then
				-- Single line tag - remove just this portion
				local before = line:sub(1, open_start - 1)
				local after = line:sub(open_start + 2 + same_line_close + 1)
				lines[i] = before .. after
				-- If line is now empty or just whitespace, remove it
				if lines[i]:match("^%s*$") then
					table.remove(lines, i)
				else
					i = i + 1
				end
				removed = removed + 1
			else
				-- Multi-line tag - find the closing line
				for j = i, #lines do
					if lines[j]:find("@/") then
						close_line = j
						close_end = lines[j]:find("@/")
						break
					end
				end

				if close_end then
					-- Remove lines from i to close_line
					-- Keep content before /@ on first line and after @/ on last line
					local before = lines[i]:sub(1, open_start - 1)
					local after = lines[close_line]:sub(close_end + 2)

					-- Remove the lines containing the tag
					for _ = i, close_line do
						table.remove(lines, i)
					end

					-- If there's content to keep, insert it back
					local remaining = (before .. after):match("^%s*(.-)%s*$")
					if remaining and remaining ~= "" then
						table.insert(lines, i, remaining)
						i = i + 1
					end

					removed = removed + 1
				else
					-- No closing tag found, skip this line
					i = i + 1
				end
			end
		else
			i = i + 1
		end
	end

	if removed > 0 then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	return removed
end

--- Check if it's safe to modify the buffer (not in insert mode)
---@return boolean
local function is_safe_to_modify()
	local mode = vim.fn.mode()
	-- Don't modify if in insert mode or completion is visible
	if mode == "i" or mode == "ic" or mode == "ix" then
		return false
	end
	if vim.fn.pumvisible() == 1 then
		return false
	end
	return true
end

--- Apply a patch to the target buffer
---@param patch PatchCandidate
---@return boolean success
---@return string|nil error
function M.apply(patch)
	-- Check if safe to modify (not in insert mode)
	if not is_safe_to_modify() then
		return false, "user_typing"
	end

	-- Check staleness first
	local is_stale, stale_reason = M.is_stale(patch)
	if is_stale then
		M.mark_stale(patch.id, stale_reason)

		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "warning",
				message = string.format("Patch %s is stale: %s", patch.id, stale_reason or "unknown"),
			})
		end)

		return false, "patch_stale: " .. (stale_reason or "unknown")
	end

	-- Ensure target buffer is valid
	local target_bufnr = patch.target_bufnr
	if target_bufnr == -1 or not vim.api.nvim_buf_is_valid(target_bufnr) then
		-- Try to load buffer from path
		target_bufnr = vim.fn.bufadd(patch.target_path)
		if target_bufnr == 0 then
			M.mark_rejected(patch.id, "buffer_not_found")
			return false, "target buffer not found"
		end
		vim.fn.bufload(target_bufnr)
		patch.target_bufnr = target_bufnr
	end

	-- Prepare code lines
	local code_lines = vim.split(patch.generated_code, "\n", { plain = true })

	-- FIRST: Remove the prompt tags from the buffer before applying code
	-- This prevents the infinite loop where tags stay and get re-detected
	local tags_removed = remove_prompt_tags(target_bufnr)

	pcall(function()
		if tags_removed > 0 then
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "info",
				message = string.format("Removed %d prompt tag(s) from buffer", tags_removed),
			})
		end
	end)

	-- Recalculate line count after tag removal
	local line_count = vim.api.nvim_buf_line_count(target_bufnr)

	-- Apply based on strategy
	local ok, err = pcall(function()
		if patch.injection_strategy == "replace" and patch.injection_range then
			-- Replace the scope range with the new code
			-- The injection_range points to the function/method we're completing
			local start_line = patch.injection_range.start_line
			local end_line = patch.injection_range.end_line

			-- Adjust for tag removal - find the new range by searching for the scope
			-- After removing tags, line numbers may have shifted
			-- Use the scope information to find the correct range
			if patch.scope and patch.scope.type then
				-- Try to find the scope using treesitter if available
				local found_range = nil
				pcall(function()
					local ts_utils = require("nvim-treesitter.ts_utils")
					local parsers = require("nvim-treesitter.parsers")
					local parser = parsers.get_parser(target_bufnr)
					if parser then
						local tree = parser:parse()[1]
						if tree then
							local root = tree:root()
							-- Find the function/method node that contains our original position
							local function find_scope_node(node)
								local node_type = node:type()
								local is_scope = node_type:match("function")
									or node_type:match("method")
									or node_type:match("class")
									or node_type:match("declaration")

								if is_scope then
									local s_row, _, e_row, _ = node:range()
									-- Check if this scope roughly matches our expected range
									if math.abs(s_row - (start_line - 1)) <= 5 then
										found_range = { start_line = s_row + 1, end_line = e_row + 1 }
										return true
									end
								end

								for child in node:iter_children() do
									if find_scope_node(child) then
										return true
									end
								end
								return false
							end
							find_scope_node(root)
						end
					end
				end)

				if found_range then
					start_line = found_range.start_line
					end_line = found_range.end_line
				end
			end

			-- Clamp to valid range
			start_line = math.max(1, start_line)
			end_line = math.min(line_count, end_line)

			-- Replace the range (0-indexed for nvim_buf_set_lines)
			vim.api.nvim_buf_set_lines(target_bufnr, start_line - 1, end_line, false, code_lines)

			pcall(function()
				local logs = require("codetyper.agent.logs")
				logs.add({
					type = "info",
					message = string.format("Replacing lines %d-%d with %d lines of code", start_line, end_line, #code_lines),
				})
			end)
		elseif patch.injection_strategy == "insert" and patch.injection_range then
			-- Insert at the specified location
			local insert_line = patch.injection_range.start_line
			insert_line = math.max(1, math.min(line_count + 1, insert_line))
			vim.api.nvim_buf_set_lines(target_bufnr, insert_line - 1, insert_line - 1, false, code_lines)
		else
			-- Default: append to end
			-- Check if last line is empty, if not add a blank line for spacing
			local last_line = vim.api.nvim_buf_get_lines(target_bufnr, line_count - 1, line_count, false)[1] or ""
			if last_line:match("%S") then
				-- Last line has content, add blank line for spacing
				table.insert(code_lines, 1, "")
			end
			vim.api.nvim_buf_set_lines(target_bufnr, line_count, line_count, false, code_lines)
		end
	end)

	if not ok then
		M.mark_rejected(patch.id, err)
		return false, err
	end

	M.mark_applied(patch.id)

	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "success",
			message = string.format("Patch %s applied successfully", patch.id),
			data = {
				target_path = patch.target_path,
				lines_added = #code_lines,
			},
		})
	end)

	return true, nil
end

--- Flush all pending patches that are safe to apply
---@return number applied_count
---@return number stale_count
---@return number deferred_count
function M.flush_pending()
	local applied = 0
	local stale = 0
	local deferred = 0

	for _, p in ipairs(patches) do
		if p.status == "pending" then
			local success, err = M.apply(p)
			if success then
				applied = applied + 1
			elseif err == "user_typing" then
				-- Keep pending, will retry later
				deferred = deferred + 1
			else
				stale = stale + 1
			end
		end
	end

	return applied, stale, deferred
end

--- Cancel all pending patches for a buffer
---@param bufnr number
---@return number cancelled_count
function M.cancel_for_buffer(bufnr)
	local cancelled = 0
	for _, patch in ipairs(patches) do
		if patch.status == "pending" and
			(patch.target_bufnr == bufnr or patch.original_snapshot.bufnr == bufnr) then
			patch.status = "cancelled"
			cancelled = cancelled + 1
		end
	end
	return cancelled
end

--- Cleanup old patches
---@param max_age number Max age in seconds (default: 300)
function M.cleanup(max_age)
	max_age = max_age or 300
	local now = os.time()
	local i = 1
	while i <= #patches do
		local patch = patches[i]
		if patch.status ~= "pending" and (now - patch.created_at) > max_age then
			table.remove(patches, i)
		else
			i = i + 1
		end
	end
end

--- Get statistics
---@return table
function M.stats()
	local stats = {
		total = #patches,
		pending = 0,
		applied = 0,
		stale = 0,
		rejected = 0,
		cancelled = 0,
	}
	for _, patch in ipairs(patches) do
		local s = patch.status
		if stats[s] then
			stats[s] = stats[s] + 1
		end
	end
	return stats
end

--- Clear all patches
function M.clear()
	patches = {}
end

return M
