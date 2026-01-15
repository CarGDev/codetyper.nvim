---@mod codetyper.agent.queue Event queue for prompt processing
---@brief [[
--- Priority queue system for PromptEvents with observer pattern.
--- Events are processed by priority (1=high, 2=normal, 3=low).
---@brief ]]

local M = {}

---@class AttachedFile
---@field path string Relative path as referenced in prompt
---@field full_path string Absolute path to the file
---@field content string File content

---@class PromptEvent
---@field id string Unique event ID
---@field bufnr number Source buffer number
---@field range {start_line: number, end_line: number} Line range of prompt tag
---@field timestamp number os.clock() timestamp
---@field changedtick number Buffer changedtick snapshot
---@field content_hash string Hash of prompt region
---@field prompt_content string Cleaned prompt text
---@field target_path string Target file for injection
---@field priority number Priority (1=high, 2=normal, 3=low)
---@field status string "pending"|"processing"|"completed"|"escalated"|"cancelled"|"needs_context"|"failed"
---@field attempt_count number Number of processing attempts
---@field worker_type string|nil LLM provider used ("ollama"|"openai"|"gemini"|"copilot")
---@field created_at number System time when created
---@field intent Intent|nil Detected intent from prompt
---@field scope ScopeInfo|nil Resolved scope (function/class/file)
---@field scope_text string|nil Text of the resolved scope
---@field scope_range {start_line: number, end_line: number}|nil Range of scope in target
---@field attached_files AttachedFile[]|nil Files attached via @filename syntax

--- Internal state
---@type PromptEvent[]
local queue = {}

--- Event listeners (observer pattern)
---@type function[]
local listeners = {}

--- Event ID counter
local event_counter = 0

--- Generate unique event ID
---@return string
function M.generate_id()
	event_counter = event_counter + 1
	return string.format("evt_%d_%d", os.time(), event_counter)
end

--- Simple hash function for content
---@param content string
---@return string
function M.hash_content(content)
	local hash = 0
	for i = 1, #content do
		hash = (hash * 31 + string.byte(content, i)) % 2147483647
	end
	return string.format("%x", hash)
end

--- Notify all listeners of queue change
---@param event_type string "enqueue"|"dequeue"|"update"|"cancel"
---@param event PromptEvent|nil The affected event
local function notify_listeners(event_type, event)
	for _, listener in ipairs(listeners) do
		pcall(listener, event_type, event, #queue)
	end
end

--- Add event listener
---@param callback function(event_type: string, event: PromptEvent|nil, queue_size: number)
---@return number Listener ID for removal
function M.add_listener(callback)
	table.insert(listeners, callback)
	return #listeners
end

--- Remove event listener
---@param listener_id number
function M.remove_listener(listener_id)
	if listener_id > 0 and listener_id <= #listeners then
		table.remove(listeners, listener_id)
	end
end

--- Compare events for priority sorting
---@param a PromptEvent
---@param b PromptEvent
---@return boolean
local function compare_priority(a, b)
	-- Lower priority number = higher priority
	if a.priority ~= b.priority then
		return a.priority < b.priority
	end
	-- Same priority: older events first (FIFO)
	return a.timestamp < b.timestamp
end

--- Check if two events are in the same scope
---@param a PromptEvent
---@param b PromptEvent
---@return boolean
local function same_scope(a, b)
	-- Same buffer
	if a.target_path ~= b.target_path then
		return false
	end

	-- Both have scope ranges
	if a.scope_range and b.scope_range then
		-- Check if ranges overlap
		return a.scope_range.start_line <= b.scope_range.end_line
			and b.scope_range.start_line <= a.scope_range.end_line
	end

	-- Fallback: check if prompt ranges are close (within 10 lines)
	if a.range and b.range then
		local distance = math.abs(a.range.start_line - b.range.start_line)
		return distance < 10
	end

	return false
end

--- Find conflicting events in the same scope
---@param event PromptEvent
---@return PromptEvent[] Conflicting pending events
function M.find_conflicts(event)
	local conflicts = {}
	for _, existing in ipairs(queue) do
		if existing.status == "pending" and existing.id ~= event.id then
			if same_scope(event, existing) then
				table.insert(conflicts, existing)
			end
		end
	end
	return conflicts
end

--- Check if an event should be skipped due to conflicts (first tag wins)
---@param event PromptEvent
---@return boolean should_skip
---@return string|nil reason
function M.check_precedence(event)
	local conflicts = M.find_conflicts(event)

	for _, conflict in ipairs(conflicts) do
		-- First (older) tag wins
		if conflict.timestamp < event.timestamp then
			return true, string.format(
				"Skipped: earlier tag in same scope (event %s)",
				conflict.id
			)
		end
	end

	return false, nil
end

--- Insert event maintaining priority order
---@param event PromptEvent
local function insert_sorted(event)
	local pos = #queue + 1
	for i, existing in ipairs(queue) do
		if compare_priority(event, existing) then
			pos = i
			break
		end
	end
	table.insert(queue, pos, event)
end

--- Enqueue a new event
---@param event PromptEvent
---@return PromptEvent The enqueued event with generated ID if missing
function M.enqueue(event)
	-- Ensure required fields
	event.id = event.id or M.generate_id()
	event.timestamp = event.timestamp or os.clock()
	event.created_at = event.created_at or os.time()
	event.status = event.status or "pending"
	event.priority = event.priority or 2
	event.attempt_count = event.attempt_count or 0

	-- Generate content hash if not provided
	if not event.content_hash and event.prompt_content then
		event.content_hash = M.hash_content(event.prompt_content)
	end

	insert_sorted(event)
	notify_listeners("enqueue", event)

	-- Log to agent logs if available
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "queue",
			message = string.format("Event queued: %s (priority: %d)", event.id, event.priority),
			data = {
				event_id = event.id,
				bufnr = event.bufnr,
				prompt_preview = event.prompt_content:sub(1, 50),
			},
		})
	end)

	return event
end

--- Dequeue highest priority pending event
---@return PromptEvent|nil
function M.dequeue()
	for i, event in ipairs(queue) do
		if event.status == "pending" then
			event.status = "processing"
			notify_listeners("dequeue", event)
			return event
		end
	end
	return nil
end

--- Peek at next pending event without removing
---@return PromptEvent|nil
function M.peek()
	for _, event in ipairs(queue) do
		if event.status == "pending" then
			return event
		end
	end
	return nil
end

--- Get event by ID
---@param id string
---@return PromptEvent|nil
function M.get(id)
	for _, event in ipairs(queue) do
		if event.id == id then
			return event
		end
	end
	return nil
end

--- Update event status
---@param id string
---@param status string
---@param extra table|nil Additional fields to update
---@return boolean Success
function M.update_status(id, status, extra)
	for _, event in ipairs(queue) do
		if event.id == id then
			event.status = status
			if extra then
				for k, v in pairs(extra) do
					event[k] = v
				end
			end
			notify_listeners("update", event)
			return true
		end
	end
	return false
end

--- Mark event as completed
---@param id string
---@return boolean
function M.complete(id)
	return M.update_status(id, "completed")
end

--- Mark event as escalated (needs remote LLM)
---@param id string
---@return boolean
function M.escalate(id)
	local event = M.get(id)
	if event then
		event.status = "escalated"
		event.attempt_count = event.attempt_count + 1
		-- Re-queue as pending with same priority
		event.status = "pending"
		notify_listeners("update", event)
		return true
	end
	return false
end

--- Cancel all events for a buffer
---@param bufnr number
---@return number Number of cancelled events
function M.cancel_for_buffer(bufnr)
	local cancelled = 0
	for _, event in ipairs(queue) do
		if event.bufnr == bufnr and event.status == "pending" then
			event.status = "cancelled"
			cancelled = cancelled + 1
			notify_listeners("cancel", event)
		end
	end
	return cancelled
end

--- Cancel event by ID
---@param id string
---@return boolean
function M.cancel(id)
	return M.update_status(id, "cancelled")
end

--- Get all pending events
---@return PromptEvent[]
function M.get_pending()
	local pending = {}
	for _, event in ipairs(queue) do
		if event.status == "pending" then
			table.insert(pending, event)
		end
	end
	return pending
end

--- Get all processing events
---@return PromptEvent[]
function M.get_processing()
	local processing = {}
	for _, event in ipairs(queue) do
		if event.status == "processing" then
			table.insert(processing, event)
		end
	end
	return processing
end

--- Get queue size (all events)
---@return number
function M.size()
	return #queue
end

--- Get count of pending events
---@return number
function M.pending_count()
	local count = 0
	for _, event in ipairs(queue) do
		if event.status == "pending" then
			count = count + 1
		end
	end
	return count
end

--- Get count of processing events
---@return number
function M.processing_count()
	local count = 0
	for _, event in ipairs(queue) do
		if event.status == "processing" then
			count = count + 1
		end
	end
	return count
end

--- Check if queue is empty (no pending events)
---@return boolean
function M.is_empty()
	return M.pending_count() == 0
end

--- Clear all events (optionally filter by status)
---@param status string|nil Status to clear, or nil for all
function M.clear(status)
	if status then
		local i = 1
		while i <= #queue do
			if queue[i].status == status then
				table.remove(queue, i)
			else
				i = i + 1
			end
		end
	else
		queue = {}
	end
	notify_listeners("update", nil)
end

--- Cleanup completed/cancelled/failed events older than max_age seconds
---@param max_age number Maximum age in seconds (default: 300)
function M.cleanup(max_age)
	max_age = max_age or 300
	local now = os.time()
	local terminal_statuses = {
		completed = true,
		cancelled = true,
		failed = true,
		needs_context = true,
	}
	local i = 1
	while i <= #queue do
		local event = queue[i]
		if terminal_statuses[event.status] and (now - event.created_at) > max_age then
			table.remove(queue, i)
		else
			i = i + 1
		end
	end
end

--- Get queue statistics
---@return table
function M.stats()
	local stats = {
		total = #queue,
		pending = 0,
		processing = 0,
		completed = 0,
		cancelled = 0,
		escalated = 0,
		failed = 0,
		needs_context = 0,
	}
	for _, event in ipairs(queue) do
		local s = event.status
		if stats[s] then
			stats[s] = stats[s] + 1
		end
	end
	return stats
end

--- Debug: dump queue contents
---@return string
function M.dump()
	local lines = { "Queue contents:" }
	for i, event in ipairs(queue) do
		table.insert(lines, string.format(
			"  %d. [%s] %s (p:%d, status:%s, attempts:%d)",
			i, event.id,
			event.prompt_content:sub(1, 30):gsub("\n", " "),
			event.priority, event.status, event.attempt_count
		))
	end
	return table.concat(lines, "\n")
end

return M
