---@mod codetyper.agent.worker Async LLM worker wrapper
---@brief [[
--- Wraps LLM clients with timeout handling and confidence scoring.
--- Provides unified interface for scheduler to dispatch work.
---@brief ]]

local M = {}

local confidence = require("codetyper.agent.confidence")

---@class WorkerResult
---@field success boolean Whether the request succeeded
---@field response string|nil The generated code
---@field error string|nil Error message if failed
---@field confidence number Confidence score (0.0-1.0)
---@field confidence_breakdown table Detailed confidence breakdown
---@field duration number Time taken in seconds
---@field worker_type string LLM provider used
---@field usage table|nil Token usage if available

---@class Worker
---@field id string Worker ID
---@field event table PromptEvent being processed
---@field worker_type string LLM provider type
---@field status string "pending"|"running"|"completed"|"failed"|"timeout"
---@field start_time number Start timestamp
---@field timeout_ms number Timeout in milliseconds
---@field timer any Timeout timer handle
---@field callback function Result callback

--- Worker ID counter
local worker_counter = 0

--- Patterns that indicate LLM needs more context (must be near start of response)
local context_needed_patterns = {
	"^%s*i need more context",
	"^%s*i'm sorry.-i need more",
	"^%s*i apologize.-i need more",
	"^%s*could you provide more context",
	"^%s*could you please provide more",
	"^%s*can you clarify",
	"^%s*please provide more context",
	"^%s*more information needed",
	"^%s*not enough context",
	"^%s*i don't have enough",
	"^%s*unclear what you",
	"^%s*what do you mean by",
}

--- Check if response indicates need for more context
--- Only triggers if the response primarily asks for context (no substantial code)
---@param response string
---@return boolean
local function needs_more_context(response)
	if not response then
		return false
	end

	-- If response has substantial code (more than 5 lines with code-like content), don't ask for context
	local lines = vim.split(response, "\n")
	local code_lines = 0
	for _, line in ipairs(lines) do
		-- Count lines that look like code (have programming constructs)
		if line:match("[{}();=]") or line:match("function") or line:match("def ")
			or line:match("class ") or line:match("return ") or line:match("import ")
			or line:match("public ") or line:match("private ") or line:match("local ") then
			code_lines = code_lines + 1
		end
	end

	-- If there's substantial code, don't trigger context request
	if code_lines >= 3 then
		return false
	end

	-- Check if the response STARTS with a context-needed phrase
	local lower = response:lower()
	for _, pattern in ipairs(context_needed_patterns) do
		if lower:match(pattern) then
			return true
		end
	end
	return false
end

--- Clean LLM response to extract only code
---@param response string Raw LLM response
---@param filetype string|nil File type for language detection
---@return string Cleaned code
local function clean_response(response, filetype)
	if not response then
		return ""
	end

	local cleaned = response

	-- Remove LLM special tokens (deepseek, llama, etc.)
	cleaned = cleaned:gsub("<｜begin▁of▁sentence｜>", "")
	cleaned = cleaned:gsub("<｜end▁of▁sentence｜>", "")
	cleaned = cleaned:gsub("<|im_start|>", "")
	cleaned = cleaned:gsub("<|im_end|>", "")
	cleaned = cleaned:gsub("<s>", "")
	cleaned = cleaned:gsub("</s>", "")
	cleaned = cleaned:gsub("<|endoftext|>", "")

	-- Remove the original prompt tags /@ ... @/ if they appear in output
	-- Use [%s%S] to match any character including newlines (Lua's . doesn't match newlines)
	cleaned = cleaned:gsub("/@[%s%S]-@/", "")

	-- Try to extract code from markdown code blocks
	-- Match ```language\n...\n``` or just ```\n...\n```
	local code_block = cleaned:match("```[%w]*\n(.-)\n```")
	if not code_block then
		-- Try without newline after language
		code_block = cleaned:match("```[%w]*(.-)\n```")
	end
	if not code_block then
		-- Try single line code block
		code_block = cleaned:match("```(.-)```")
	end

	if code_block then
		cleaned = code_block
	else
		-- No code block found, try to remove common prefixes/suffixes
		-- Remove common apology/explanation phrases at the start
		local explanation_starts = {
			"^[Ii]'m sorry.-\n",
			"^[Ii] apologize.-\n",
			"^[Hh]ere is.-:\n",
			"^[Hh]ere's.-:\n",
			"^[Tt]his is.-:\n",
			"^[Bb]ased on.-:\n",
			"^[Ss]ure.-:\n",
			"^[Oo][Kk].-:\n",
			"^[Cc]ertainly.-:\n",
		}
		for _, pattern in ipairs(explanation_starts) do
			cleaned = cleaned:gsub(pattern, "")
		end

		-- Remove trailing explanations
		local explanation_ends = {
			"\n[Tt]his code.-$",
			"\n[Tt]his function.-$",
			"\n[Tt]his is a.-$",
			"\n[Ii] hope.-$",
			"\n[Ll]et me know.-$",
			"\n[Ff]eel free.-$",
			"\n[Nn]ote:.-$",
			"\n[Pp]lease replace.-$",
			"\n[Pp]lease note.-$",
			"\n[Yy]ou might want.-$",
			"\n[Yy]ou may want.-$",
			"\n[Mm]ake sure.-$",
			"\n[Aa]lso,.-$",
			"\n[Rr]emember.-$",
		}
		for _, pattern in ipairs(explanation_ends) do
			cleaned = cleaned:gsub(pattern, "")
		end
	end

	-- Remove any remaining markdown artifacts
	cleaned = cleaned:gsub("^```[%w]*\n?", "")
	cleaned = cleaned:gsub("\n?```$", "")

	-- Trim whitespace
	cleaned = cleaned:match("^%s*(.-)%s*$") or cleaned

	return cleaned
end

--- Active workers
---@type table<string, Worker>
local active_workers = {}

--- Default timeouts by provider type
local default_timeouts = {
	ollama = 30000,   -- 30s for local
	claude = 60000,   -- 60s for remote
	openai = 60000,
	gemini = 60000,
	copilot = 60000,
}

--- Generate worker ID
---@return string
local function generate_id()
	worker_counter = worker_counter + 1
	return string.format("worker_%d_%d", os.time(), worker_counter)
end

--- Get LLM client by type
---@param worker_type string
---@return table|nil client
---@return string|nil error
local function get_client(worker_type)
	local ok, client = pcall(require, "codetyper.llm." .. worker_type)
	if ok and client then
		return client, nil
	end
	return nil, "Unknown provider: " .. worker_type
end

--- Format attached files for inclusion in prompt
---@param attached_files table[]|nil
---@return string
local function format_attached_files(attached_files)
	if not attached_files or #attached_files == 0 then
		return ""
	end

	local parts = { "\n\n--- Referenced Files ---" }
	for _, file in ipairs(attached_files) do
		local ext = vim.fn.fnamemodify(file.path, ":e")
		table.insert(parts, string.format(
			"\n\nFile: %s\n```%s\n%s\n```",
			file.path,
			ext,
			file.content:sub(1, 3000) -- Limit each file to 3000 chars
		))
	end

	return table.concat(parts, "")
end

--- Build prompt for code generation
---@param event table PromptEvent
---@return string prompt
---@return table context
local function build_prompt(event)
	local intent_mod = require("codetyper.agent.intent")

	-- Get target file content for context
	local target_content = ""
	if event.target_path then
		local ok, lines = pcall(function()
			return vim.fn.readfile(event.target_path)
		end)
		if ok and lines then
			target_content = table.concat(lines, "\n")
		end
	end

	local filetype = vim.fn.fnamemodify(event.target_path or "", ":e")

	-- Format attached files
	local attached_content = format_attached_files(event.attached_files)

	-- Build context with scope information
	local context = {
		target_path = event.target_path,
		target_content = target_content,
		filetype = filetype,
		scope = event.scope,
		scope_text = event.scope_text,
		scope_range = event.scope_range,
		intent = event.intent,
		attached_files = event.attached_files,
	}

	-- Build the actual prompt based on intent and scope
	local system_prompt = ""
	local user_prompt = event.prompt_content

	if event.intent then
		system_prompt = intent_mod.get_prompt_modifier(event.intent)
	end

	-- If we have a scope (function/method), include it in the prompt
	if event.scope_text and event.scope and event.scope.type ~= "file" then
		local scope_type = event.scope.type
		local scope_name = event.scope.name or "anonymous"

		-- Special handling for "complete" intent - fill in the function body
		if event.intent and event.intent.type == "complete" then
			user_prompt = string.format(
				[[Complete this %s. Fill in the implementation based on the description.

IMPORTANT:
- Keep the EXACT same function signature (name, parameters, return type)
- Only provide the COMPLETE function with implementation
- Do NOT create a new function or duplicate the signature
- Do NOT add any text before or after the function

Current %s (incomplete):
```%s
%s
```
%s
What it should do: %s

Return ONLY the complete %s with implementation. No explanations, no duplicates.]],
				scope_type,
				scope_type,
				filetype,
				event.scope_text,
				attached_content,
				event.prompt_content,
				scope_type
			)
		-- For other replacement intents, provide the full scope to transform
		elseif event.intent and intent_mod.is_replacement(event.intent) then
			user_prompt = string.format(
				[[Here is a %s named "%s" in a %s file:

```%s
%s
```
%s
User request: %s

Return the complete transformed %s. Output only code, no explanations.]],
				scope_type,
				scope_name,
				filetype,
				filetype,
				event.scope_text,
				attached_content,
				event.prompt_content,
				scope_type
			)
		else
			-- For insertion intents, provide context
			user_prompt = string.format(
				[[Context - this code is inside a %s named "%s":

```%s
%s
```
%s
User request: %s

Output only the code to insert, no explanations.]],
				scope_type,
				scope_name,
				filetype,
				event.scope_text,
				attached_content,
				event.prompt_content
			)
		end
	else
		-- No scope resolved, use full file context
		user_prompt = string.format(
			[[File: %s (%s)

```%s
%s
```
%s
User request: %s

Output only code, no explanations.]],
			vim.fn.fnamemodify(event.target_path or "", ":t"),
			filetype,
			filetype,
			target_content:sub(1, 4000), -- Limit context size
			attached_content,
			event.prompt_content
		)
	end

	context.system_prompt = system_prompt
	context.formatted_prompt = user_prompt

	return user_prompt, context
end

--- Create and start a worker
---@param event table PromptEvent
---@param worker_type string LLM provider type
---@param callback function(result: WorkerResult)
---@return Worker
function M.create(event, worker_type, callback)
	local worker = {
		id = generate_id(),
		event = event,
		worker_type = worker_type,
		status = "pending",
		start_time = os.clock(),
		timeout_ms = default_timeouts[worker_type] or 60000,
		callback = callback,
	}

	active_workers[worker.id] = worker

	-- Log worker creation
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "worker",
			message = string.format("Worker %s started (%s)", worker.id, worker_type),
			data = {
				worker_id = worker.id,
				event_id = event.id,
				provider = worker_type,
			},
		})
	end)

	-- Start the work
	M.start(worker)

	return worker
end

--- Start worker execution
---@param worker Worker
function M.start(worker)
	worker.status = "running"

	-- Set up timeout
	worker.timer = vim.defer_fn(function()
		if worker.status == "running" then
			worker.status = "timeout"
			active_workers[worker.id] = nil

			pcall(function()
				local logs = require("codetyper.agent.logs")
				logs.add({
					type = "warning",
					message = string.format("Worker %s timed out after %dms", worker.id, worker.timeout_ms),
				})
			end)

			worker.callback({
				success = false,
				response = nil,
				error = "timeout",
				confidence = 0,
				confidence_breakdown = {},
				duration = (os.clock() - worker.start_time),
				worker_type = worker.worker_type,
			})
		end
	end, worker.timeout_ms)

	-- Get client and execute
	local client, client_err = get_client(worker.worker_type)
	if not client then
		M.complete(worker, nil, client_err)
		return
	end

	local prompt, context = build_prompt(worker.event)

	-- Call the LLM
	client.generate(prompt, context, function(response, err, usage)
		-- Cancel timeout timer
		if worker.timer then
			pcall(function()
				-- Timer might have already fired
				if type(worker.timer) == "userdata" and worker.timer.stop then
					worker.timer:stop()
				end
			end)
		end

		if worker.status ~= "running" then
			return -- Already timed out or cancelled
		end

		M.complete(worker, response, err, usage)
	end)
end

--- Complete worker execution
---@param worker Worker
---@param response string|nil
---@param error string|nil
---@param usage table|nil
function M.complete(worker, response, error, usage)
	local duration = os.clock() - worker.start_time

	if error then
		worker.status = "failed"
		active_workers[worker.id] = nil

		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "error",
				message = string.format("Worker %s failed: %s", worker.id, error),
			})
		end)

		worker.callback({
			success = false,
			response = nil,
			error = error,
			confidence = 0,
			confidence_breakdown = {},
			duration = duration,
			worker_type = worker.worker_type,
			usage = usage,
		})
		return
	end

	-- Check if LLM needs more context
	if needs_more_context(response) then
		worker.status = "needs_context"
		active_workers[worker.id] = nil

		pcall(function()
			local logs = require("codetyper.agent.logs")
			logs.add({
				type = "info",
				message = string.format("Worker %s: LLM needs more context", worker.id),
			})
		end)

		worker.callback({
			success = false,
			response = response,
			error = nil,
			needs_context = true,
			original_event = worker.event,
			confidence = 0,
			confidence_breakdown = {},
			duration = duration,
			worker_type = worker.worker_type,
			usage = usage,
		})
		return
	end

	-- Log the full raw LLM response (for debugging)
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "response",
			message = "--- LLM Response ---",
			data = {
				raw_response = response,
			},
		})
	end)

	-- Clean the response (remove markdown, explanations, etc.)
	local filetype = vim.fn.fnamemodify(worker.event.target_path or "", ":e")
	local cleaned_response = clean_response(response, filetype)

	-- Score confidence on cleaned response
	local conf_score, breakdown = confidence.score(cleaned_response, worker.event.prompt_content)

	worker.status = "completed"
	active_workers[worker.id] = nil

	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "success",
			message = string.format(
				"Worker %s completed (%.2fs, confidence: %.2f - %s)",
				worker.id, duration, conf_score, confidence.level_name(conf_score)
			),
			data = {
				confidence_breakdown = confidence.format_breakdown(breakdown),
				usage = usage,
			},
		})
	end)

	worker.callback({
		success = true,
		response = cleaned_response,
		error = nil,
		confidence = conf_score,
		confidence_breakdown = breakdown,
		duration = duration,
		worker_type = worker.worker_type,
		usage = usage,
	})
end

--- Cancel a worker
---@param worker_id string
---@return boolean
function M.cancel(worker_id)
	local worker = active_workers[worker_id]
	if not worker then
		return false
	end

	if worker.timer then
		pcall(function()
			if type(worker.timer) == "userdata" and worker.timer.stop then
				worker.timer:stop()
			end
		end)
	end

	worker.status = "cancelled"
	active_workers[worker_id] = nil

	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "info",
			message = string.format("Worker %s cancelled", worker_id),
		})
	end)

	return true
end

--- Get active worker count
---@return number
function M.active_count()
	local count = 0
	for _ in pairs(active_workers) do
		count = count + 1
	end
	return count
end

--- Get all active workers
---@return Worker[]
function M.get_active()
	local workers = {}
	for _, worker in pairs(active_workers) do
		table.insert(workers, worker)
	end
	return workers
end

--- Check if worker exists and is running
---@param worker_id string
---@return boolean
function M.is_running(worker_id)
	local worker = active_workers[worker_id]
	return worker ~= nil and worker.status == "running"
end

--- Cancel all workers for an event
---@param event_id string
---@return number cancelled_count
function M.cancel_for_event(event_id)
	local cancelled = 0
	for id, worker in pairs(active_workers) do
		if worker.event.id == event_id then
			M.cancel(id)
			cancelled = cancelled + 1
		end
	end
	return cancelled
end

--- Set timeout for worker type
---@param worker_type string
---@param timeout_ms number
function M.set_timeout(worker_type, timeout_ms)
	default_timeouts[worker_type] = timeout_ms
end

return M
