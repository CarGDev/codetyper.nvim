---@mod codetyper.agent.scheduler Event scheduler with completion-awareness
---@brief [[
--- Central orchestrator for the event-driven system.
--- Handles dispatch, escalation, and completion-safe injection.
---@brief ]]

local M = {}

local queue = require("codetyper.agent.queue")
local patch = require("codetyper.agent.patch")
local worker = require("codetyper.agent.worker")
local confidence_mod = require("codetyper.agent.confidence")
local context_modal = require("codetyper.agent.context_modal")

--- Scheduler state
local state = {
	running = false,
	timer = nil,
	poll_interval = 100, -- ms
	paused = false,
	config = {
		enabled = true,
		ollama_scout = true,
		escalation_threshold = 0.7,
		max_concurrent = 2,
		completion_delay_ms = 100,
		remote_provider = "claude", -- Default fallback provider
	},
}

--- Autocommand group for injection timing
local augroup = nil

--- Check if completion popup is visible
---@return boolean
function M.is_completion_visible()
	-- Check native popup menu
	if vim.fn.pumvisible() == 1 then
		return true
	end

	-- Check nvim-cmp
	local ok, cmp = pcall(require, "cmp")
	if ok and cmp.visible and cmp.visible() then
		return true
	end

	-- Check coq_nvim
	local coq_ok, coq = pcall(require, "coq")
	if coq_ok and coq and type(coq.visible) == "function" and coq.visible() then
		return true
	end

	return false
end

--- Check if we're in insert mode
---@return boolean
function M.is_insert_mode()
	local mode = vim.fn.mode()
	return mode == "i" or mode == "ic" or mode == "ix"
end

--- Check if it's safe to inject code
---@return boolean
---@return string|nil reason if not safe
function M.is_safe_to_inject()
	if M.is_completion_visible() then
		return false, "completion_visible"
	end

	if M.is_insert_mode() then
		return false, "insert_mode"
	end

	return true, nil
end

--- Get the provider for escalation
---@return string
local function get_remote_provider()
	local ok, codetyper = pcall(require, "codetyper")
	if ok then
		local config = codetyper.get_config()
		if config and config.llm and config.llm.provider then
			-- If current provider is ollama, use configured remote
			if config.llm.provider == "ollama" then
				-- Check which remote provider is configured
				if config.llm.claude and config.llm.claude.api_key then
					return "claude"
				elseif config.llm.openai and config.llm.openai.api_key then
					return "openai"
				elseif config.llm.gemini and config.llm.gemini.api_key then
					return "gemini"
				elseif config.llm.copilot then
					return "copilot"
				end
			end
			return config.llm.provider
		end
	end
	return state.config.remote_provider
end

--- Get the primary provider (ollama if scout enabled, else configured)
---@return string
local function get_primary_provider()
	if state.config.ollama_scout then
		return "ollama"
	end

	local ok, codetyper = pcall(require, "codetyper")
	if ok then
		local config = codetyper.get_config()
		if config and config.llm and config.llm.provider then
			return config.llm.provider
		end
	end
	return "claude"
end

--- Retry event with additional context
---@param original_event table Original prompt event
---@param additional_context string Additional context from user
local function retry_with_context(original_event, additional_context)
	-- Create new prompt content combining original + additional
	local combined_prompt = string.format(
		"%s\n\nAdditional context:\n%s",
		original_event.prompt_content,
		additional_context
	)

	-- Create a new event with the combined prompt
	local new_event = vim.deepcopy(original_event)
	new_event.id = nil -- Will be assigned a new ID
	new_event.prompt_content = combined_prompt
	new_event.attempt_count = 0
	new_event.status = nil

	-- Log the retry
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "info",
			message = string.format("Retrying with additional context (original: %s)", original_event.id),
		})
	end)

	-- Queue the new event
	queue.enqueue(new_event)
end

--- Process worker result and decide next action
---@param event table PromptEvent
---@param result table WorkerResult
local function handle_worker_result(event, result)
	-- Check if LLM needs more context
	if result.needs_context then
		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "info",
				message = string.format("Event %s: LLM needs more context, opening modal", event.id),
			})
		end)

		-- Open the context modal
		context_modal.open(result.original_event or event, result.response or "", retry_with_context)

		-- Mark original event as needing context (not failed)
		queue.update_status(event.id, "needs_context", { response = result.response })
		return
	end

	if not result.success then
		-- Failed - try escalation if this was ollama
		if result.worker_type == "ollama" and event.attempt_count < 2 then
			pcall(function()
				local logs = require("codetyper.agent.logs")
				logs.add({
					type = "info",
					message = string.format(
						"Escalating event %s to remote provider (ollama failed)",
						event.id
					),
				})
			end)

			event.attempt_count = event.attempt_count + 1
			event.status = "pending"
			event.worker_type = get_remote_provider()
			return
		end

		-- Mark as failed
		queue.update_status(event.id, "failed", { error = result.error })
		return
	end

	-- Success - check confidence
	local needs_escalation = confidence_mod.needs_escalation(
		result.confidence,
		state.config.escalation_threshold
	)

	if needs_escalation and result.worker_type == "ollama" and event.attempt_count < 2 then
		-- Low confidence from ollama - escalate to remote
		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "info",
				message = string.format(
					"Escalating event %s to remote provider (confidence: %.2f < %.2f)",
					event.id, result.confidence, state.config.escalation_threshold
				),
			})
		end)

		event.attempt_count = event.attempt_count + 1
		event.status = "pending"
		event.worker_type = get_remote_provider()
		return
	end

	-- Good enough or final attempt - create patch
	local p = patch.create_from_event(event, result.response, result.confidence)
	patch.queue_patch(p)

	queue.complete(event.id)

	-- Schedule patch application
	M.schedule_patch_flush()
end

--- Dispatch next event from queue
local function dispatch_next()
	if state.paused then
		return
	end

	-- Check concurrent limit
	if worker.active_count() >= state.config.max_concurrent then
		return
	end

	-- Get next pending event
	local event = queue.dequeue()
	if not event then
		return
	end

	-- Check for precedence conflicts (multiple tags in same scope)
	local should_skip, skip_reason = queue.check_precedence(event)
	if should_skip then
		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "warning",
				message = string.format("Event %s skipped: %s", event.id, skip_reason or "conflict"),
			})
		end)
		queue.cancel(event.id)
		-- Try next event
		return dispatch_next()
	end

	-- Determine which provider to use
	local provider = event.worker_type or get_primary_provider()

	-- Log dispatch with intent/scope info
	pcall(function()
		local logs = require("codetyper.agent.logs")
		local intent_info = event.intent and event.intent.type or "unknown"
		local scope_info = event.scope and event.scope.type ~= "file"
			and string.format("%s:%s", event.scope.type, event.scope.name or "anon")
			or "file"
		logs.add({
			type = "info",
			message = string.format(
				"Dispatching %s [intent: %s, scope: %s, provider: %s]",
				event.id, intent_info, scope_info, provider
			),
		})
	end)

	-- Create worker
	worker.create(event, provider, function(result)
		vim.schedule(function()
			handle_worker_result(event, result)
		end)
	end)
end

--- Schedule patch flush after delay (completion safety)
function M.schedule_patch_flush()
	vim.defer_fn(function()
		local safe, reason = M.is_safe_to_inject()
		if safe then
			local applied, stale = patch.flush_pending()
			if applied > 0 or stale > 0 then
				pcall(function()
					local logs = require("codetyper.agent.logs")
					logs.add({
						type = "info",
						message = string.format("Patches flushed: %d applied, %d stale", applied, stale),
					})
				end)
			end
		else
			-- Not safe yet, reschedule
			pcall(function()
				local logs = require("codetyper.agent.logs")
				logs.add({
					type = "debug",
					message = string.format("Patch flush deferred: %s", reason or "unknown"),
				})
			end)
			-- Will be retried on next InsertLeave or CursorHold
		end
	end, state.config.completion_delay_ms)
end

--- Main scheduler loop
local function scheduler_loop()
	if not state.running then
		return
	end

	dispatch_next()

	-- Cleanup old items periodically
	if math.random() < 0.01 then -- ~1% chance each tick
		queue.cleanup(300)
		patch.cleanup(300)
	end

	-- Schedule next tick
	state.timer = vim.defer_fn(scheduler_loop, state.poll_interval)
end

--- Setup autocommands for injection timing
local function setup_autocmds()
	if augroup then
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
	end

	augroup = vim.api.nvim_create_augroup("CodetypeScheduler", { clear = true })

	-- Flush patches when leaving insert mode
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = augroup,
		callback = function()
			vim.defer_fn(function()
				if not M.is_completion_visible() then
					patch.flush_pending()
				end
			end, state.config.completion_delay_ms)
		end,
		desc = "Flush pending patches on InsertLeave",
	})

	-- Flush patches on cursor hold
	vim.api.nvim_create_autocmd("CursorHold", {
		group = augroup,
		callback = function()
			if not M.is_insert_mode() and not M.is_completion_visible() then
				patch.flush_pending()
			end
		end,
		desc = "Flush pending patches on CursorHold",
	})

	-- Cancel patches when buffer changes significantly
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = augroup,
		callback = function(ev)
			-- Mark relevant patches as potentially stale
			-- They'll be checked on next flush attempt
		end,
		desc = "Check patch staleness on save",
	})

	-- Cleanup when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		group = augroup,
		callback = function(ev)
			queue.cancel_for_buffer(ev.buf)
			patch.cancel_for_buffer(ev.buf)
			worker.cancel_for_event(ev.buf)
		end,
		desc = "Cleanup on buffer delete",
	})
end

--- Start the scheduler
---@param config table|nil Configuration overrides
function M.start(config)
	if state.running then
		return
	end

	-- Merge config
	if config then
		for k, v in pairs(config) do
			state.config[k] = v
		end
	end

	-- Load config from codetyper if available
	pcall(function()
		local codetyper = require("codetyper")
		local ct_config = codetyper.get_config()
		if ct_config and ct_config.scheduler then
			for k, v in pairs(ct_config.scheduler) do
				state.config[k] = v
			end
		end
	end)

	if not state.config.enabled then
		return
	end

	state.running = true
	state.paused = false

	-- Setup autocmds
	setup_autocmds()

	-- Add queue listener
	queue.add_listener(function(event_type, event, queue_size)
		if event_type == "enqueue" and not state.paused then
			-- New event - try to dispatch immediately
			vim.schedule(dispatch_next)
		end
	end)

	-- Start main loop
	scheduler_loop()

	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "info",
			message = "Scheduler started",
			data = {
				ollama_scout = state.config.ollama_scout,
				escalation_threshold = state.config.escalation_threshold,
				max_concurrent = state.config.max_concurrent,
			},
		})
	end)
end

--- Stop the scheduler
function M.stop()
	state.running = false

	if state.timer then
		pcall(function()
			if type(state.timer) == "userdata" and state.timer.stop then
				state.timer:stop()
			end
		end)
		state.timer = nil
	end

	if augroup then
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
		augroup = nil
	end

	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "info",
			message = "Scheduler stopped",
		})
	end)
end

--- Pause the scheduler (don't process new events)
function M.pause()
	state.paused = true
end

--- Resume the scheduler
function M.resume()
	state.paused = false
	vim.schedule(dispatch_next)
end

--- Check if scheduler is running
---@return boolean
function M.is_running()
	return state.running
end

--- Check if scheduler is paused
---@return boolean
function M.is_paused()
	return state.paused
end

--- Get scheduler status
---@return table
function M.status()
	return {
		running = state.running,
		paused = state.paused,
		queue_stats = queue.stats(),
		patch_stats = patch.stats(),
		active_workers = worker.active_count(),
		config = vim.deepcopy(state.config),
	}
end

--- Manually trigger dispatch
function M.dispatch()
	if state.running and not state.paused then
		dispatch_next()
	end
end

--- Force flush all pending patches (ignores completion check)
function M.force_flush()
	return patch.flush_pending()
end

--- Update configuration
---@param config table
function M.configure(config)
	for k, v in pairs(config) do
		state.config[k] = v
	end
end

return M
