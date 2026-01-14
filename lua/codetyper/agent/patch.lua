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

--- Apply a patch to the target buffer
---@param patch PatchCandidate
---@return boolean success
---@return string|nil error
function M.apply(patch)
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

	-- Apply based on strategy
	local ok, err = pcall(function()
		if patch.injection_strategy == "replace" and patch.injection_range then
			-- Replace specific range
			vim.api.nvim_buf_set_lines(
				target_bufnr,
				patch.injection_range.start_line - 1,
				patch.injection_range.end_line,
				false,
				code_lines
			)
		elseif patch.injection_strategy == "insert" and patch.injection_range then
			-- Insert at specific line
			vim.api.nvim_buf_set_lines(
				target_bufnr,
				patch.injection_range.start_line - 1,
				patch.injection_range.start_line - 1,
				false,
				code_lines
			)
		else
			-- Default: append to end
			local line_count = vim.api.nvim_buf_line_count(target_bufnr)
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
function M.flush_pending()
	local applied = 0
	local stale = 0

	for _, patch in ipairs(patches) do
		if patch.status == "pending" then
			local success, _ = M.apply(patch)
			if success then
				applied = applied + 1
			else
				stale = stale + 1
			end
		end
	end

	return applied, stale
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
