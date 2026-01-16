---@mod codetyper.agent.worker Async LLM worker wrapper
---@brief [[
--- Wraps LLM clients with timeout handling and confidence scoring.
--- Provides unified interface for scheduler to dispatch work.
---@brief ]]

local M = {}

local params = require("codetyper.params.agents.worker")
local confidence = require("codetyper.core.llm.confidence")

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
local context_needed_patterns = params.context_needed_patterns

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

--- Check if response contains SEARCH/REPLACE blocks
---@param response string
---@return boolean
local function has_search_replace_blocks(response)
	if not response then
		return false
	end
	-- Check for any of the supported SEARCH/REPLACE formats
	return response:match("<<<<<<<%s*SEARCH") ~= nil
		or response:match("%-%-%-%-%-%-%-?%s*SEARCH") ~= nil
		or response:match("%[SEARCH%]") ~= nil
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

	-- IMPORTANT: If response contains SEARCH/REPLACE blocks, preserve them!
	-- Don't extract from markdown or remove "explanations" that are actually part of the format
	if has_search_replace_blocks(cleaned) then
		-- Just trim whitespace and return - the blocks will be parsed by search_replace module
		return cleaned:match("^%s*(.-)%s*$") or cleaned
	end

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
local default_timeouts = params.default_timeouts

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

--- Get coder companion file path for a target file
---@param target_path string Target file path
---@return string|nil Coder file path if exists
local function get_coder_companion_path(target_path)
	if not target_path or target_path == "" then
		return nil
	end

	-- Skip if target is already a coder file
	if target_path:match("%.coder%.") then
		return nil
	end

	local dir = vim.fn.fnamemodify(target_path, ":h")
	local name = vim.fn.fnamemodify(target_path, ":t:r") -- filename without extension
	local ext = vim.fn.fnamemodify(target_path, ":e")

	local coder_path = dir .. "/" .. name .. ".coder." .. ext
	if vim.fn.filereadable(coder_path) == 1 then
		return coder_path
	end

	return nil
end

--- Read and format coder companion context (business logic, pseudo-code)
---@param target_path string Target file path
---@return string Formatted coder context
local function get_coder_context(target_path)
	local coder_path = get_coder_companion_path(target_path)
	if not coder_path then
		return ""
	end

	local ok, lines = pcall(function()
		return vim.fn.readfile(coder_path)
	end)

	if not ok or not lines or #lines == 0 then
		return ""
	end

	local content = table.concat(lines, "\n")

	-- Skip if only template comments (no actual content)
	local stripped = content:gsub("^%s*", ""):gsub("%s*$", "")
	if stripped == "" then
		return ""
	end

	-- Check if there's meaningful content (not just template)
	local has_content = false
	for _, line in ipairs(lines) do
		-- Skip comment lines that are part of the template
		local trimmed = line:gsub("^%s*", "")
		if not trimmed:match("^[%-#/]+%s*Coder companion")
			and not trimmed:match("^[%-#/]+%s*Use /@ @/")
			and not trimmed:match("^[%-#/]+%s*Example:")
			and not trimmed:match("^<!%-%-")
			and trimmed ~= ""
			and not trimmed:match("^[%-#/]+%s*$") then
			has_content = true
			break
		end
	end

	if not has_content then
		return ""
	end

	local ext = vim.fn.fnamemodify(coder_path, ":e")
	return string.format(
		"\n\n--- Business Context / Pseudo-code ---\n" ..
		"The following describes the intended behavior and design for this file:\n" ..
		"```%s\n%s\n```",
		ext,
		content:sub(1, 4000) -- Limit to 4000 chars
	)
end

--- Format indexed project context for inclusion in prompt
---@param indexed_context table|nil
---@return string
local function format_indexed_context(indexed_context)
	if not indexed_context then
		return ""
	end

	local parts = {}

	-- Project type
	if indexed_context.project_type and indexed_context.project_type ~= "unknown" then
		table.insert(parts, "Project type: " .. indexed_context.project_type)
	end

	-- Relevant symbols
	if indexed_context.relevant_symbols then
		local symbol_list = {}
		for symbol, files in pairs(indexed_context.relevant_symbols) do
			if #files > 0 then
				table.insert(symbol_list, symbol .. " (in " .. files[1] .. ")")
			end
		end
		if #symbol_list > 0 then
			table.insert(parts, "Relevant symbols: " .. table.concat(symbol_list, ", "))
		end
	end

	-- Learned patterns
	if indexed_context.patterns and #indexed_context.patterns > 0 then
		local pattern_list = {}
		for i, p in ipairs(indexed_context.patterns) do
			if i <= 3 then
				table.insert(pattern_list, p.content or "")
			end
		end
		if #pattern_list > 0 then
			table.insert(parts, "Project conventions: " .. table.concat(pattern_list, "; "))
		end
	end

	if #parts == 0 then
		return ""
	end

	return "\n\n--- Project Context ---\n" .. table.concat(parts, "\n")
end

--- Check if this is an inline prompt (tags in target file, not a coder file)
---@param event table
---@return boolean
local function is_inline_prompt(event)
	-- Inline prompts have a range with start_line/end_line from tag detection
	-- and the source file is the same as target (not a .coder. file)
	if not event.range or not event.range.start_line then
		return false
	end
	-- Check if source path (if any) equals target, or if target has no .coder. in it
	local target = event.target_path or ""
	if target:match("%.coder%.") then
		return false
	end
	return true
end

--- Build file content with marked region for inline prompts
---@param lines string[] File lines
---@param start_line number 1-indexed
---@param end_line number 1-indexed
---@param prompt_content string The prompt inside the tags
---@return string
local function build_marked_file_content(lines, start_line, end_line, prompt_content)
	local result = {}
	for i, line in ipairs(lines) do
		if i == start_line then
			-- Mark the start of the region to be replaced
			table.insert(result, ">>> REPLACE THIS REGION (lines " .. start_line .. "-" .. end_line .. ") <<<")
			table.insert(result, "--- User request: " .. prompt_content:gsub("\n", " "):sub(1, 100) .. " ---")
		end
		table.insert(result, line)
		if i == end_line then
			table.insert(result, ">>> END OF REGION TO REPLACE <<<")
		end
	end
	return table.concat(result, "\n")
end

--- Build prompt for code generation
---@param event table PromptEvent
---@return string prompt
---@return table context
local function build_prompt(event)
	local intent_mod = require("codetyper.core.intent")

	-- Get target file content for context
	local target_content = ""
	local target_lines = {}
	if event.target_path then
		local ok, lines = pcall(function()
			return vim.fn.readfile(event.target_path)
		end)
		if ok and lines then
			target_lines = lines
			target_content = table.concat(lines, "\n")
		end
	end

	local filetype = vim.fn.fnamemodify(event.target_path or "", ":e")

	-- Get indexed project context
	local indexed_context = nil
	local indexed_content = ""
	pcall(function()
		local indexer = require("codetyper.features.indexer")
		indexed_context = indexer.get_context_for({
			file = event.target_path,
			intent = event.intent,
			prompt = event.prompt_content,
			scope = event.scope_text,
		})
		indexed_content = format_indexed_context(indexed_context)
	end)

	-- Format attached files
	local attached_content = format_attached_files(event.attached_files)

	-- Get coder companion context (business logic, pseudo-code)
	local coder_context = get_coder_context(event.target_path)

	-- Get brain memories - contextual recall based on current task
	local brain_context = ""
	pcall(function()
		local brain = require("codetyper.core.memory")
		if brain.is_initialized() then
			-- Query brain for relevant memories based on:
			-- 1. Current file (file-specific patterns)
			-- 2. Prompt content (semantic similarity)
			-- 3. Intent type (relevant past generations)
			local query_text = event.prompt_content or ""
			if event.scope and event.scope.name then
				query_text = event.scope.name .. " " .. query_text
			end

			local result = brain.query({
				query = query_text,
				file = event.target_path,
				max_results = 5,
				types = { "pattern", "correction", "convention" },
			})

			if result and result.nodes and #result.nodes > 0 then
				local memories = { "\n\n--- Learned Patterns & Conventions ---" }
				for _, node in ipairs(result.nodes) do
					if node.c then
						local summary = node.c.s or ""
						local detail = node.c.d or ""
						if summary ~= "" then
							table.insert(memories, "• " .. summary)
							if detail ~= "" and #detail < 200 then
								table.insert(memories, "  " .. detail)
							end
						end
					end
				end
				if #memories > 1 then
					brain_context = table.concat(memories, "\n")
				end
			end
		end
	end)

	-- Combine all context sources: brain memories first, then coder context, attached files, indexed
	local extra_context = brain_context .. coder_context .. attached_content .. indexed_content

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
		indexed_context = indexed_context,
	}

	-- Build the actual prompt based on intent and scope
	local system_prompt = ""
	local user_prompt = event.prompt_content

	if event.intent then
		system_prompt = intent_mod.get_prompt_modifier(event.intent)
	end

	-- SPECIAL HANDLING: Inline prompts with /@ ... @/ tags
	-- Uses SEARCH/REPLACE block format for reliable code editing
	if is_inline_prompt(event) and event.range and event.range.start_line then
		local start_line = event.range.start_line
		local end_line = event.range.end_line or start_line

		-- Build full file content WITHOUT the /@ @/ tags for cleaner context
		local file_content_clean = {}
		for i, line in ipairs(target_lines) do
			-- Skip lines that are part of the tag
			if i < start_line or i > end_line then
				table.insert(file_content_clean, line)
			end
		end

		user_prompt = string.format(
			[[You are editing a %s file: %s

TASK: %s

FULL FILE CONTENT:
```%s
%s
```

IMPORTANT: The instruction above may ask you to make changes ANYWHERE in the file (e.g., "at the top", "after function X", etc.). Read the instruction carefully to determine WHERE to apply the change.

INSTRUCTIONS:
You MUST respond using SEARCH/REPLACE blocks. This format lets you precisely specify what to find and what to replace it with.

FORMAT:
<<<<<<< SEARCH
[exact lines to find in the file - copy them exactly including whitespace]
=======
[new lines to replace them with]
>>>>>>> REPLACE

RULES:
1. The SEARCH section must contain EXACT lines from the file (copy-paste them)
2. Include 2-3 context lines to uniquely identify the location
3. The REPLACE section contains the modified code
4. You can use multiple SEARCH/REPLACE blocks for multiple changes
5. Preserve the original indentation style
6. If adding new code at the start/end of file, include the first/last few lines in SEARCH

EXAMPLES:

Example 1 - Adding code at the TOP of file:
Task: "Add a comment at the top"
<<<<<<< SEARCH
// existing first line
// existing second line
=======
// NEW COMMENT ADDED HERE
// existing first line
// existing second line
>>>>>>> REPLACE

Example 2 - Modifying a function:
Task: "Add validation to setValue"
<<<<<<< SEARCH
export function setValue(key, value) {
  cache.set(key, value);
}
=======
export function setValue(key, value) {
  if (!key) throw new Error("key required");
  cache.set(key, value);
}
>>>>>>> REPLACE

Now apply the requested changes using SEARCH/REPLACE blocks:]],
			filetype,
			vim.fn.fnamemodify(event.target_path or "", ":t"),
			event.prompt_content,
			filetype,
			table.concat(file_content_clean, "\n"):sub(1, 8000) -- Limit size
		)

		context.system_prompt = system_prompt
		context.formatted_prompt = user_prompt
		context.is_inline_prompt = true
		context.use_search_replace = true

		return user_prompt, context
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
				extra_context,
				event.prompt_content,
				scope_type
			)
			-- Remind the LLM not to repeat the original file content; ask for only the new/updated code or a unified diff
			user_prompt = user_prompt .. [[

IMPORTANT: Do NOT repeat the existing code provided above. Return ONLY the new or modified code (the updated function body). If you modify the file, prefer outputting a unified diff patch using standard diff headers (--- a/<file> / +++ b/<file> and @@ hunks). No explanations, no markdown, no code fences.
]]
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
				extra_context,
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
				extra_context,
				event.prompt_content
			)

			-- Remind the LLM not to repeat the full file content; ask for only the new/modified code or unified diff
			user_prompt = user_prompt .. [[

IMPORTANT: Do NOT repeat the full file content shown above. Return ONLY the new or modified code required to satisfy the request. If you modify the file, prefer outputting a unified diff patch using standard diff headers (--- a/<file> / +++ b/<file> and @@ hunks). No explanations, no markdown, no code fences.
]]

			-- Remind the LLM not to repeat the original file content; ask for only the inserted code or a unified diff
			user_prompt = user_prompt .. [[

IMPORTANT: Do NOT repeat the surrounding code provided above. Return ONLY the code to insert (the new snippet). If you modify multiple parts of the file, prefer outputting a unified diff patch using standard diff headers (--- a/<file> / +++ b/<file> and @@ hunks). No explanations, no markdown, no code fences.
]]
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
			extra_context,
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
		local logs = require("codetyper.adapters.nvim.ui.logs")
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
				local logs = require("codetyper.adapters.nvim.ui.logs")
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

	local prompt, context = build_prompt(worker.event)

	-- Check if smart selection is enabled (memory-based provider selection)
	local use_smart_selection = false
	pcall(function()
		local codetyper = require("codetyper")
		local config = codetyper.get_config()
		use_smart_selection = config.llm.smart_selection ~= false -- Default to true
	end)

	-- Define the response handler
	local function handle_response(response, err, usage_or_metadata)
		-- Cancel timeout timer
		if worker.timer then
			pcall(function()
				if type(worker.timer) == "userdata" and worker.timer.stop then
					worker.timer:stop()
				end
			end)
		end

		if worker.status ~= "running" then
			return -- Already timed out or cancelled
		end

		-- Extract usage from metadata if smart_generate was used
		local usage = usage_or_metadata
		if type(usage_or_metadata) == "table" and usage_or_metadata.provider then
			-- This is metadata from smart_generate
			usage = nil
			-- Update worker type to reflect actual provider used
			worker.worker_type = usage_or_metadata.provider
			-- Log if pondering occurred
			if usage_or_metadata.pondered then
				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "info",
						message = string.format(
							"Pondering: %s (agreement: %.0f%%)",
							usage_or_metadata.corrected and "corrected" or "validated",
							(usage_or_metadata.agreement or 1) * 100
						),
					})
				end)
			end
		end

		M.complete(worker, response, err, usage)
	end

	-- Use smart selection or direct client
	if use_smart_selection then
		local llm = require("codetyper.core.llm")
		llm.smart_generate(prompt, context, handle_response)
	else
		-- Get client and execute directly
		local client, client_err = get_client(worker.worker_type)
		if not client then
			M.complete(worker, nil, client_err)
			return
		end
		client.generate(prompt, context, handle_response)
	end
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
			local logs = require("codetyper.adapters.nvim.ui.logs")
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
			local logs = require("codetyper.adapters.nvim.ui.logs")
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
		local logs = require("codetyper.adapters.nvim.ui.logs")
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
		local logs = require("codetyper.adapters.nvim.ui.logs")
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
		local logs = require("codetyper.adapters.nvim.ui.logs")
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
