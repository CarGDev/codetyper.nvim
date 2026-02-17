---@mod codetyper.agent.patch Patch system with staleness detection
---@brief [[
--- Manages code patches with buffer snapshots for staleness detection.
--- Patches are queued for safe injection when completion popup is not visible.
--- Uses SEARCH/REPLACE blocks for reliable code editing.
---@brief ]]

local M = {}

local params = require("codetyper.params.agents.patch")
local logger = require("codetyper.support.logger")


--- Lazy load inject module to avoid circular requires
local function get_inject_module()
	return require("codetyper.inject")
end

--- Lazy load search_replace module
local function get_search_replace_module()
	return require("codetyper.core.diff.search_replace")
end

--- Lazy load conflict module
local function get_conflict_module()
	return require("codetyper.core.diff.conflict")
end

--- Configuration for patch behavior
local config = params.config

---@class BufferSnapshot
---@field bufnr number Buffer number
---@field changedtick number vim.b.changedtick at snapshot time
---@field content_hash string Hash of buffer content in range
---@field range {start_line: number, end_line: number}|nil Range snapshotted

---@class PatchCandidate
---@field id string Unique patch ID
---@field event_id string Related PromptEvent ID
---@field source_bufnr number Source buffer where prompt tags are (coder file)
---@field target_bufnr number Target buffer for injection (real file)
---@field target_path string Target file path
---@field original_snapshot BufferSnapshot Snapshot at event creation
---@field generated_code string Code to inject
---@field injection_range {start_line: number, end_line: number}|nil
---@field injection_strategy string "append"|"replace"|"insert"|"search_replace"
---@field confidence number Confidence score (0.0-1.0)
---@field status string "pending"|"applied"|"stale"|"rejected"
---@field created_at number Timestamp
---@field applied_at number|nil When applied
---@field use_search_replace boolean Whether to use SEARCH/REPLACE block parsing
---@field search_replace_blocks table[]|nil Parsed SEARCH/REPLACE blocks

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
		local logs = require("codetyper.adapters.nvim.ui.logs")
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
	-- Source buffer is where the prompt tags are (could be coder file)
	local source_bufnr = event.bufnr

	-- Get target buffer (where code should be injected - the real file)
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

	-- Detect if this is an inline prompt (source == target, not a .coder. file)
	local is_inline = (source_bufnr == target_bufnr) or
		(event.target_path and not event.target_path:match("%.coder%."))

	-- Take snapshot of the scope range in target buffer (for staleness detection)
	local snapshot_range = event.scope_range or event.range
	local snapshot = M.snapshot_buffer(
		target_bufnr ~= -1 and target_bufnr or event.bufnr,
		snapshot_range
	)

	-- Check if the response contains SEARCH/REPLACE blocks
	local search_replace = get_search_replace_module()
	local sr_blocks = search_replace.parse_blocks(generated_code)
	local use_search_replace = #sr_blocks > 0

	-- Determine injection strategy and range based on intent
	local injection_strategy = strategy
	local injection_range = nil

	-- Handle intent_override from transform-selection (e.g., cursor insert mode)
	if event.intent_override and event.intent_override.action then
		injection_strategy = event.intent_override.action
		-- Use injection_range from transform-selection, not event.range
		injection_range = event.injection_range or (event.range and {
			start_line = event.range.start_line,
			end_line = event.range.end_line,
		})
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "info",
				message = string.format("Using override strategy: %s (%s)", injection_strategy,
					injection_range and (injection_range.start_line .. "-" .. injection_range.end_line) or "nil"),
			})
		end)
	-- If we have SEARCH/REPLACE blocks, use that strategy
	elseif use_search_replace then
		injection_strategy = "search_replace"
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "info",
				message = string.format("Using SEARCH/REPLACE mode with %d block(s)", #sr_blocks),
			})
		end)
	elseif is_inline and event.range then
		-- Inline prompts: always replace the selection (we asked LLM for "code that replaces lines X-Y")
		injection_strategy = "replace"
		local start_line = math.max(1, event.range.start_line or 1)
		local end_line = math.max(1, event.range.end_line or 1)
		if end_line < start_line then
			end_line = start_line
		end
		-- Prefer scope_range if event.range is invalid (0-0) and we have scope
		if (event.range.start_line == 0 or event.range.end_line == 0) and event.scope_range then
			start_line = math.max(1, event.scope_range.start_line or 1)
			end_line = math.max(1, event.scope_range.end_line or 1)
			if end_line < start_line then
				end_line = start_line
			end
		end
		injection_range = { start_line = start_line, end_line = end_line }
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "info",
				message = string.format("Inline: replace lines %d-%d", start_line, end_line),
			})
		end)
	elseif not injection_strategy and event.intent then
		local intent_mod = require("codetyper.core.intent")
		if intent_mod.is_replacement(event.intent) then
			injection_strategy = "replace"

			-- INLINE PROMPTS: Always use tag range
			-- The LLM is told specifically to replace the tagged region
			if is_inline and event.range then
				injection_range = {
					start_line = event.range.start_line,
					end_line = event.range.end_line,
				}
				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "info",
						message = string.format("Inline prompt: will replace tag region (lines %d-%d)",
							event.range.start_line, event.range.end_line),
					})
				end)
			-- CODER FILES: Use scope range for replacement
			elseif event.scope_range then
				injection_range = event.scope_range
			else
				-- Fallback: no scope found (treesitter didn't find function)
				-- Use tag range - the generated code will replace the tag region
				injection_range = {
					start_line = event.range.start_line,
					end_line = event.range.end_line,
				}
				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "warning",
						message = "No scope found, using tag range as fallback",
					})
				end)
			end
		elseif event.intent.action == "insert" then
			injection_strategy = "insert"
			-- Insert at prompt location (use full tag range)
			injection_range = { start_line = event.range.start_line, end_line = event.range.end_line }
		elseif event.intent.action == "append" then
			injection_strategy = "append"
			-- Will append to end of file
		else
			injection_strategy = "append"
		end
	end

	injection_strategy = injection_strategy or "append"

	local range_str = injection_range
		and string.format("%d-%d", injection_range.start_line, injection_range.end_line)
		or "nil"
	logger.info("patch", string.format(
		"create: is_inline=%s strategy=%s range=%s use_sr=%s intent_action=%s",
		tostring(is_inline),
		injection_strategy,
		range_str,
		tostring(use_search_replace),
		event.intent and event.intent.action or "nil"
	))

	return {
		id = M.generate_id(),
		event_id = event.id,
		source_bufnr = source_bufnr, -- Where prompt tags are (coder file)
		target_bufnr = target_bufnr, -- Where code goes (real file)
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
		-- Mark if this is an inline prompt (tags in source file, not coder file)
		is_inline_prompt = is_inline,
		-- SEARCH/REPLACE support
		use_search_replace = use_search_replace,
		search_replace_blocks = use_search_replace and sr_blocks or nil,
		-- Extmarks for injection range (99-style: apply at current position after user edits)
		injection_marks = event.injection_marks,
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

--- Check if it's safe to modify the buffer (not in insert or visual mode)
---@return boolean
local function is_safe_to_modify()
	local mode = vim.fn.mode()
	-- Don't modify if in insert mode, visual mode, or completion is visible
	if mode == "i" or mode == "ic" or mode == "ix" then
		return false
	end
	-- Visual modes: v (char), V (line), \22 (block)
	if mode == "v" or mode == "V" or mode == "\22" then
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
	logger.info("patch", string.format("apply() entered: id=%s strategy=%s has_range=%s", patch.id, tostring(patch.injection_strategy), patch.injection_range and "yes" or "no"))

	-- Check if safe to modify (not in insert or visual mode)
	if not is_safe_to_modify() then
		logger.info("patch", "apply aborted: not safe (insert/visual mode or pum visible)")
		return false, "user_typing"
	end

	-- Check staleness (skip when we have valid extmarks - 99-style: position tracked across edits)
	local is_stale, stale_reason = true, nil
	if patch.injection_marks and patch.injection_marks.start_mark and patch.injection_marks.end_mark then
		local marks_mod = require("codetyper.core.marks")
		if marks_mod.is_valid(patch.injection_marks.start_mark) and marks_mod.is_valid(patch.injection_marks.end_mark) then
			is_stale = false
		end
	end
	if is_stale then
		is_stale, stale_reason = M.is_stale(patch)
	end
	if is_stale then
		M.mark_stale(patch.id, stale_reason)
		logger.warn("patch", string.format("Patch %s is stale: %s", patch.id, stale_reason or "unknown"))
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

	-- Prepare code to inject (may be overwritten when SEARCH/REPLACE fails and we use REPLACE parts only)
	local code_to_inject = patch.generated_code
	local code_lines = vim.split(patch.generated_code, "\n", { plain = true })

	-- Replace in-buffer thinking placeholder with actual code (if we inserted one when worker started).
	-- Skip when patch uses SEARCH/REPLACE: that path needs the original buffer content and parses blocks itself.
	local thinking_placeholder = require("codetyper.core.thinking_placeholder")
	local ph = thinking_placeholder.get(patch.event_id)
	if ph and ph.bufnr and vim.api.nvim_buf_is_valid(ph.bufnr)
		and not (patch.use_search_replace and patch.search_replace_blocks and #patch.search_replace_blocks > 0) then
		local marks_mod = require("codetyper.core.marks")
		if marks_mod.is_valid(ph.start_mark) and marks_mod.is_valid(ph.end_mark) then
			local sr, sc, er, ec = marks_mod.range_to_vim(ph.start_mark, ph.end_mark)
			if sr ~= nil then
				vim.api.nvim_buf_set_text(ph.bufnr, sr, sc, er, ec, code_lines)
				thinking_placeholder.clear(patch.event_id)
				M.mark_applied(patch.id)
				return true
			end
		end
		thinking_placeholder.clear(patch.event_id)
	end

	-- Use the stored inline prompt flag (computed during patch creation)
	-- For inline prompts, we replace the tag region directly instead of separate remove + inject
	local source_bufnr = patch.source_bufnr
	local is_inline_prompt = patch.is_inline_prompt or (source_bufnr == target_bufnr)
	local tags_removed = 0

	-- For CODER FILES (source != target): Remove tags from source, inject into target
	-- For INLINE PROMPTS (source == target): Include tag range in injection, no separate removal
	if not is_inline_prompt and source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
		tags_removed = remove_prompt_tags(source_bufnr)

		pcall(function()
			if tags_removed > 0 then
				local logs = require("codetyper.adapters.nvim.ui.logs")
				local source_name = vim.api.nvim_buf_get_name(source_bufnr)
				logs.add({
					type = "info",
					message = string.format("Removed %d prompt tag(s) from %s",
						tags_removed,
						vim.fn.fnamemodify(source_name, ":t")),
				})
			end
		end)
	end

	-- Get filetype for smart injection
	local filetype = vim.fn.fnamemodify(patch.target_path or "", ":e")

	-- SEARCH/REPLACE MODE: Use fuzzy matching to find and replace text
	if patch.use_search_replace and patch.search_replace_blocks and #patch.search_replace_blocks > 0 then
		local search_replace = get_search_replace_module()

		-- Remove the /@ @/ tags first (they shouldn't be in the file anymore)
		if is_inline_prompt and source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
			tags_removed = remove_prompt_tags(source_bufnr)
			if tags_removed > 0 then
				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "info",
						message = string.format("Removed %d prompt tag(s)", tags_removed),
					})
				end)
			end
		end

		-- Apply SEARCH/REPLACE blocks
		local success, err = search_replace.apply_to_buffer(target_bufnr, patch.search_replace_blocks)

		if success then
			M.mark_applied(patch.id)

			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "success",
					message = string.format("Patch %s applied via SEARCH/REPLACE (%d block(s))",
						patch.id, #patch.search_replace_blocks),
					data = {
						target_path = patch.target_path,
						blocks_applied = #patch.search_replace_blocks,
					},
				})
			end)

			-- Learn from successful code generation
			pcall(function()
				local brain = require("codetyper.core.memory")
				if brain.is_initialized() then
					local intent_type = patch.intent and patch.intent.type or "unknown"
					brain.learn({
						type = "code_completion",
						file = patch.target_path,
						timestamp = os.time(),
						data = {
							intent = intent_type,
							method = "search_replace",
							language = filetype,
							confidence = patch.confidence or 0.5,
						},
					})
				end
			end)

			return true, nil
		else
			-- SEARCH/REPLACE failed: use only REPLACE parts for fallback (never inject raw markers)
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "warning",
					message = string.format("SEARCH/REPLACE failed: %s. Using REPLACE content only for injection.", err or "unknown"),
				})
			end)
			local replace_only = {}
			for _, block in ipairs(patch.search_replace_blocks) do
				if block.replace and block.replace ~= "" then
					for _, line in ipairs(vim.split(block.replace, "\n", { plain = true })) do
						table.insert(replace_only, line)
					end
				end
			end
			if #replace_only > 0 then
				code_lines = replace_only
				code_to_inject = table.concat(replace_only, "\n")
			end
			-- Fall through to line-based injection
		end
	end

	-- Use smart injection module for intelligent import handling
	local inject = get_inject_module()
	local inject_result = nil

	local has_range = patch.injection_range ~= nil
	local apply_msg = string.format("apply: id=%s strategy=%s has_range=%s is_inline=%s target_bufnr=%s",
		patch.id,
		patch.injection_strategy or "nil",
		tostring(has_range),
		tostring(is_inline_prompt),
		tostring(target_bufnr))
	logger.info("patch", apply_msg)

	-- Apply based on strategy using smart injection
	local ok, err = pcall(function()
		-- Prepare injection options
		local inject_opts = {
			strategy = patch.injection_strategy,
			filetype = filetype,
			sort_imports = true,
		}

		if patch.injection_strategy == "replace" and patch.injection_range then
			-- Replace the scope range with the new code
			local start_line = patch.injection_range.start_line
			local end_line = patch.injection_range.end_line

			-- 99-style: use extmarks so we apply at current position (survives user typing)
			local marks = require("codetyper.core.marks")
			if patch.injection_marks and patch.injection_marks.start_mark and patch.injection_marks.end_mark then
				local sm, em = patch.injection_marks.start_mark, patch.injection_marks.end_mark
				if marks.is_valid(sm) and marks.is_valid(em) then
					local sr, sc, er, ec = marks.range_to_vim(sm, em)
					if sr ~= nil then
						start_line = sr + 1
						end_line = er + 1
						pcall(function()
							local logs = require("codetyper.adapters.nvim.ui.logs")
							logs.add({
								type = "info",
								message = string.format("Applying at extmark range (lines %d-%d)", start_line, end_line),
							})
						end)
						marks.delete(sm)
						marks.delete(em)
					end
				end
			end

			-- For inline prompts, use scope range directly (tags are inside scope)
			-- No adjustment needed since we didn't remove tags yet
			if not is_inline_prompt and patch.scope and patch.scope.type then
				-- For coder files, tags were already removed, so we may need to find the scope again
				local found_range = nil
				pcall(function()
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
			local line_count = vim.api.nvim_buf_line_count(target_bufnr)
			start_line = math.max(1, start_line)
			end_line = math.min(line_count, end_line)

			inject_opts.range = { start_line = start_line, end_line = end_line }
		elseif patch.injection_strategy == "insert" and patch.injection_range then
			-- For inline prompts with "insert" strategy, replace the TAG RANGE
			-- (the tag itself gets replaced with the new code)
			if is_inline_prompt and patch.prompt_tag_range then
				inject_opts.range = {
					start_line = patch.prompt_tag_range.start_line,
					end_line = patch.prompt_tag_range.end_line
				}
				-- Switch to replace strategy for the tag range
				inject_opts.strategy = "replace"
			else
				inject_opts.range = { start_line = patch.injection_range.start_line }
			end
		end

		-- Log inline prompt handling
		if is_inline_prompt then
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "info",
					message = string.format("Inline prompt: replacing lines %d-%d",
						inject_opts.range and inject_opts.range.start_line or 0,
						inject_opts.range and inject_opts.range.end_line or 0),
				})
			end)
		end

		-- Diagnostic: log inject_opts before calling inject (why injection might not run)
		local range_str = inject_opts.range
			and string.format("%d-%d", inject_opts.range.start_line, inject_opts.range.end_line)
			or "nil"
		logger.info("patch", string.format(
			"inject_opts: strategy=%s range=%s code_len=%d",
			inject_opts.strategy or "nil",
			range_str,
			code_to_inject and #code_to_inject or 0
		))

		if not inject_opts.range then
			logger.warn("patch", string.format(
				"inject has no range (strategy=%s) - inject may append or skip",
				tostring(patch.injection_strategy)
			))
		end

		-- Use smart injection - handles imports automatically
		inject_result = inject.inject(target_bufnr, code_to_inject, inject_opts)

		-- Log injection details
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			if inject_result.imports_added > 0 then
				logs.add({
					type = "info",
					message = string.format(
						"%s %d import(s), injected %d body line(s)",
						inject_result.imports_merged and "Merged" or "Added",
						inject_result.imports_added,
						inject_result.body_lines
					),
				})
			else
				logs.add({
					type = "info",
					message = string.format("Injected %d line(s) of code", inject_result.body_lines),
				})
			end
		end)
	end)

	if not ok then
		logger.error("patch", string.format("inject failed: %s", tostring(err)))
		M.mark_rejected(patch.id, err)
		return false, err
	end

	local body_lines = inject_result and inject_result.body_lines or "nil"
	logger.info("patch", string.format("inject done: body_lines=%s", tostring(body_lines)))

	M.mark_applied(patch.id)

	pcall(function()
		local logs = require("codetyper.adapters.nvim.ui.logs")
		logs.add({
			type = "success",
			message = string.format("Patch %s applied successfully", patch.id),
			data = {
				target_path = patch.target_path,
				lines_added = #code_lines,
			},
		})
	end)

	-- Learn from successful code generation - this builds neural pathways
	-- The more code is successfully applied, the better the brain becomes
	pcall(function()
		local brain = require("codetyper.core.memory")
		if brain.is_initialized() then
			-- Learn the successful pattern
			local intent_type = patch.intent and patch.intent.type or "unknown"
			local scope_type = patch.scope and patch.scope.type or "file"
			local scope_name = patch.scope and patch.scope.name or ""

			-- Create a meaningful summary for this learning
			local summary = string.format(
				"Generated %s: %s %s in %s",
				intent_type,
				scope_type,
				scope_name ~= "" and scope_name or "",
				vim.fn.fnamemodify(patch.target_path or "", ":t")
			)

			brain.learn({
				type = "code_completion",
				file = patch.target_path,
				timestamp = os.time(),
				data = {
					intent = intent_type,
					code = patch.generated_code:sub(1, 500), -- Store first 500 chars
					language = vim.fn.fnamemodify(patch.target_path or "", ":e"),
					function_name = scope_name,
					prompt = patch.prompt_content,
					confidence = patch.confidence or 0.5,
				},
			})
		end
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

--- Configure patch behavior
---@param opts table Configuration options
---   - use_conflict_mode: boolean Use conflict markers instead of direct apply
---   - auto_jump_to_conflict: boolean Auto-jump to first conflict after applying
function M.configure(opts)
	if opts.use_conflict_mode ~= nil then
		config.use_conflict_mode = opts.use_conflict_mode
	end
	if opts.auto_jump_to_conflict ~= nil then
		config.auto_jump_to_conflict = opts.auto_jump_to_conflict
	end
end

--- Get current configuration
---@return table
function M.get_config()
	return vim.deepcopy(config)
end

--- Check if conflict mode is enabled
---@return boolean
function M.is_conflict_mode()
	return config.use_conflict_mode
end

--- Apply a patch using conflict markers for interactive review
--- Instead of directly replacing code, inserts git-style conflict markers
---@param patch PatchCandidate
---@return boolean success
---@return string|nil error
function M.apply_with_conflict(patch)
	-- Check if safe to modify (not in insert mode)
	if not is_safe_to_modify() then
		return false, "user_typing"
	end

	-- Check staleness first
	local is_stale, stale_reason = M.is_stale(patch)
	if is_stale then
		M.mark_stale(patch.id, stale_reason)
		return false, "patch_stale: " .. (stale_reason or "unknown")
	end

	-- Ensure target buffer is valid
	local target_bufnr = patch.target_bufnr
	if target_bufnr == -1 or not vim.api.nvim_buf_is_valid(target_bufnr) then
		target_bufnr = vim.fn.bufadd(patch.target_path)
		if target_bufnr == 0 then
			M.mark_rejected(patch.id, "buffer_not_found")
			return false, "target buffer not found"
		end
		vim.fn.bufload(target_bufnr)
		patch.target_bufnr = target_bufnr
	end

	local conflict = get_conflict_module()
	local source_bufnr = patch.source_bufnr
	local is_inline_prompt = patch.is_inline_prompt or (source_bufnr == target_bufnr)

	-- Remove tags from coder files
	if not is_inline_prompt and source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
		remove_prompt_tags(source_bufnr)
	end

	-- For SEARCH/REPLACE blocks, convert each block to a conflict
	if patch.use_search_replace and patch.search_replace_blocks and #patch.search_replace_blocks > 0 then
		local search_replace = get_search_replace_module()
		local content = table.concat(vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false), "\n")
		local applied_count = 0

		-- Sort blocks by position (bottom to top) to maintain line numbers
		local sorted_blocks = {}
		for _, block in ipairs(patch.search_replace_blocks) do
			local match = search_replace.find_match(content, block.search)
			if match then
				block._match = match
				table.insert(sorted_blocks, block)
			end
		end
		table.sort(sorted_blocks, function(a, b)
			return (a._match and a._match.start_line or 0) > (b._match and b._match.start_line or 0)
		end)

		-- Apply each block as a conflict
		for _, block in ipairs(sorted_blocks) do
			local match = block._match
			if match then
				local new_lines = vim.split(block.replace, "\n", { plain = true })
				conflict.insert_conflict(
					target_bufnr,
					match.start_line,
					match.end_line,
					new_lines,
					"AI SUGGESTION"
				)
				applied_count = applied_count + 1
				-- Re-read content for next match (line numbers changed)
				content = table.concat(vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false), "\n")
			end
		end

		if applied_count > 0 then
			-- Remove tags for inline prompts after inserting conflicts
			if is_inline_prompt and source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
				remove_prompt_tags(source_bufnr)
			end

			-- Process conflicts (highlight, keymaps) and show menu
			conflict.process_and_show_menu(target_bufnr)

			M.mark_applied(patch.id)

			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "success",
					message = string.format(
						"Created %d conflict(s) for review - use co/ct/cb/cn to resolve",
						applied_count
					),
				})
			end)

			return true, nil
		end
	end

	-- Fallback: Use injection range if available
	if patch.injection_range then
		local start_line = patch.injection_range.start_line
		local end_line = patch.injection_range.end_line
		local new_lines = vim.split(patch.generated_code, "\n", { plain = true })

		-- Remove tags for inline prompts
		if is_inline_prompt and source_bufnr and vim.api.nvim_buf_is_valid(source_bufnr) then
			remove_prompt_tags(source_bufnr)
		end

		-- Insert conflict markers
		conflict.insert_conflict(target_bufnr, start_line, end_line, new_lines, "AI SUGGESTION")

		-- Process conflicts (highlight, keymaps) and show menu
		conflict.process_and_show_menu(target_bufnr)

		M.mark_applied(patch.id)

		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "success",
				message = "Created conflict for review - use co/ct/cb/cn to resolve",
			})
		end)

		return true, nil
	end

	-- No suitable range found, fall back to direct apply
	return M.apply(patch)
end

--- Smart apply - uses conflict mode if enabled, otherwise direct apply
---@param patch PatchCandidate
---@return boolean success
---@return string|nil error
function M.smart_apply(patch)
	if config.use_conflict_mode then
		return M.apply_with_conflict(patch)
	else
		return M.apply(patch)
	end
end

--- Flush all pending patches using smart apply
---@return number applied_count
---@return number stale_count
---@return number deferred_count
function M.flush_pending_smart()
	local applied = 0
	local stale = 0
	local deferred = 0

	for _, p in ipairs(patches) do
		if p.status == "pending" then
			logger.info("patch", string.format("flush trying: id=%s", p.id))
			local success, err = M.smart_apply(p)
			if success then
				applied = applied + 1
				logger.info("patch", string.format("flush result: id=%s success", p.id))
			elseif err == "user_typing" then
				deferred = deferred + 1
				logger.info("patch", string.format("flush result: id=%s deferred (user_typing)", p.id))
			else
				stale = stale + 1
				logger.info("patch", string.format("flush result: id=%s stale (%s)", p.id, tostring(err)))
			end
		end
	end

	return applied, stale, deferred
end

return M
