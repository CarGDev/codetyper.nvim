---@mod codetyper.agent.worker Async LLM worker wrapper
---@brief [[
--- Wraps LLM clients with confidence scoring.
--- Provides unified interface for scheduler to dispatch work.
---@brief ]]

local M = {}

local params = require("codetyper.params.agents.worker")
local confidence = require("codetyper.core.llm.confidence")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

---@class WorkerResult
---@field success boolean Whether the request succeeded
---@field response string|nil The generated code or explanation text
---@field error string|nil Error message if failed
---@field is_explanation boolean|nil True if response is thinking-only (show, don't inject)
---@field confidence number Confidence score (0.0-1.0)
---@field confidence_breakdown table Detailed confidence breakdown
---@field duration number Time taken in seconds
---@field worker_type string LLM provider used
---@field usage table|nil Token usage if available

---@class Worker
---@field id string Worker ID
---@field event table PromptEvent being processed
---@field worker_type string LLM provider type
---@field status string "pending"|"running"|"completed"|"failed"
---@field start_time number Start timestamp
---@field callback function Result callback

--- Worker ID counter
local worker_counter = 0

--- Broadcast a stage update to inline placeholder, thinking window, and vim.notify.
---@param event_id string|nil
---@param text string Status text
local function notify_stage(event_id, text)
  pcall(function()
    local tp = require("codetyper.core.thinking_placeholder")
    if event_id then
      tp.update_inline_status(event_id, text)
    end
  end)
  pcall(function()
    local thinking_update_stage = require("codetyper.adapters.nvim.ui.thinking.update_stage")
    thinking_update_stage(text)
  end)
end

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
    if
      line:match("[{}();=]")
      or line:match("function")
      or line:match("def ")
      or line:match("class ")
      or line:match("return ")
      or line:match("import ")
      or line:match("public ")
      or line:match("private ")
      or line:match("local ")
    then
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
--- Extract the content inside @thinking ... end thinking block.
---@param text string Raw response
---@return string|nil Thinking content or nil if no block
local function extract_thinking_content(text)
  if not text or text == "" then
    return nil
  end
  local thinking = text:match("^%s*@thinking%s*\n(.-)\nend thinking")
  if thinking then
    return thinking:match("^%s*(.-)%s*$") or thinking
  end
  return nil
end

--- Strip @thinking ... end thinking block; return only the code part for injection.
---@param text string Raw response that may start with @thinking ... end thinking
---@return string Text with thinking block removed (or original if no block)
local function strip_thinking_block(text)
  if not text or text == "" then
    return text or ""
  end
  -- Match from start: @thinking, any content, then line "end thinking"; capture everything after that
  local after = text:match("^%s*@thinking[%s%S]*\nend thinking%s*\n(.*)")
  if after then
    return after:match("^%s*(.-)%s*$") or after
  end
  return text
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

  -- Remove @thinking ... end thinking block first (we show thinking in placeholder; inject only code)
  cleaned = strip_thinking_block(cleaned)

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

--- Max age in seconds before a stale worker is pruned
local WORKER_MAX_AGE = 300

--- Prune stale workers that have been running longer than WORKER_MAX_AGE
local function prune_stale()
  local now = os.clock()
  for id, worker in pairs(active_workers) do
    if now - worker.start_time > WORKER_MAX_AGE then
      worker.status = "timeout"
      active_workers[id] = nil
      pcall(function()
        local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
        logs_add({
          type = "warn",
          message = string.format("Worker %s pruned (stale after %ds)", id, WORKER_MAX_AGE),
        })
      end)
    end
  end
end

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
  local ok, client = pcall(require, "codetyper.core.llm.providers." .. worker_type)
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
    table.insert(
      parts,
      string.format(
        "\n\nFile: %s\n```%s\n%s\n```",
        file.path,
        ext,
        file.content:sub(1, 3000) -- Limit each file to 3000 chars
      )
    )
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
  if target_path:match("%.codetyper%.") then
    return nil
  end

  local dir = vim.fn.fnamemodify(target_path, ":h")
  local name = vim.fn.fnamemodify(target_path, ":t:r") -- filename without extension
  local ext = vim.fn.fnamemodify(target_path, ":e")

  local coder_path = dir .. "/" .. name .. ".codetyper/" .. ext
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
    if
      not trimmed:match("^[%-#/]+%s*Coder companion")
      and not trimmed:match("^[%-#/]+%s*Use /@ @/")
      and not trimmed:match("^[%-#/]+%s*Example:")
      and not trimmed:match("^<!%-%-")
      and trimmed ~= ""
      and not trimmed:match("^[%-#/]+%s*$")
    then
      has_content = true
      break
    end
  end

  if not has_content then
    return ""
  end

  local ext = vim.fn.fnamemodify(coder_path, ":e")
  return string.format(
    "\n\n--- Business Context / Pseudo-code ---\n"
      .. "The following describes the intended behavior and design for this file:\n"
      .. "```%s\n%s\n```",
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
  -- and the source file is the same as target (not a .codetyper/ file)
  if not event.range or not event.range.start_line then
    return false
  end
  -- Check if source path (if any) equals target, or if target has no .codetyper/ in it
  local target = event.target_path or ""
  if target:match("%.codetyper%.") then
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

--- Build prompt using the tier system
---@param event table PromptEvent
---@param model string|nil Model name for tier selection
---@return string prompt
---@return table context
local function build_prompt(event, model)
  local eid = event and event.id
  local gather_context = require("codetyper.core.llm.shared.build_context")
  local tier_router = require("codetyper.prompts.tiers")

  notify_stage(eid, "Gathering context...")
  local ctx = gather_context(event)

  notify_stage(eid, "Building prompt...")
  local user_prompt, system_prompt = tier_router.build_prompt(model or "copilot", event, ctx)

  local context = {
    target_path = event.target_path,
    target_content = ctx.target_content,
    filetype = ctx.filetype,
    scope = event.scope,
    scope_text = event.scope_text,
    scope_range = event.scope_range,
    intent = event.intent,
    attached_files = event.attached_files,
    system_prompt = system_prompt,
    formatted_prompt = user_prompt,
  }

  return user_prompt, context
end

--- Create and start a worker
---@param event table PromptEvent
---@param worker_type string LLM provider type
---@param callback function(result: WorkerResult)
---@return Worker
function M.create(event, worker_type, callback)
  flog.info("worker", string.format(">>> create: event=%s provider=%s", event.id or "nil", worker_type or "nil")) -- TODO: remove after debugging
  prune_stale()
  local worker = {
    id = generate_id(),
    event = event,
    worker_type = worker_type,
    status = "pending",
    start_time = os.clock(),
    callback = callback,
  }

  active_workers[worker.id] = worker

  -- Log worker creation
  pcall(function()
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
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
  local eid = worker.event and worker.event.id
  flog.info("worker", string.format(">>> start: id=%s event=%s", worker.id, eid or "nil")) -- TODO: remove after debugging

  notify_stage(eid, "Reading context...")

  -- Resolve model name for tier selection
  local model_name = nil
  pcall(function()
    local credentials = require("codetyper.config.credentials")
    model_name = credentials.get_model(worker.worker_type)
  end)
  if not model_name then
    model_name = worker.worker_type or "copilot"
  end

  local prompt, context = build_prompt(worker.event, model_name)
  flog.info("worker", string.format("prompt built: model=%s len=%d", model_name, #(prompt or ""))) -- TODO: remove after debugging
  flog.debug("worker", "prompt_preview: " .. (prompt and prompt:sub(1, 300):gsub("\n", "\\n") or "nil")) -- TODO: remove after debugging

  -- Check if smart selection is enabled (memory-based provider selection)
  local use_smart_selection = false
  pcall(function()
    local codetyper = require("codetyper")
    local config = codetyper.get_config()
    use_smart_selection = config.llm.smart_selection ~= false -- Default to true
  end)

  local provider_label = worker.worker_type or "LLM"
  notify_stage(eid, "Sending to " .. provider_label .. "...")

  -- Define the response handler
  local function handle_response(response, err, usage_or_metadata)
    flog.info("worker", string.format( -- TODO: remove after debugging
      ">>> handle_response: id=%s err=%s response_len=%d response_type=%s",
      worker.id, tostring(err or "nil"), response and #response or 0, type(response)
    ))
    if worker.status ~= "running" then
      flog.warn("worker", "already cancelled, ignoring response") -- TODO: remove after debugging
      return -- Already cancelled
    end

    notify_stage(eid, "Processing response...")

    -- Extract usage from metadata if smart_generate was used
    local usage = usage_or_metadata
    if type(usage_or_metadata) == "table" and usage_or_metadata.provider then
      usage = nil
      worker.worker_type = usage_or_metadata.provider
      if usage_or_metadata.pondered then
        pcall(function()
          local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
          logs_add({
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
  flog.info("worker", string.format( -- TODO: remove after debugging
    ">>> complete: id=%s duration=%.2fs error=%s response_type=%s response_len=%d",
    worker.id, duration, tostring(error or "nil"), type(response), response and #response or 0
  ))

  if error then
    worker.status = "failed"
    active_workers[worker.id] = nil

    pcall(function()
      local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
      logs_add({
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
      local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
      logs_add({
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
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
      type = "response",
      message = "--- LLM Response ---",
      data = {
        raw_response = response,
      },
    })
  end)

  -- Detect thinking-only responses: if the entire response is just a @thinking block
  -- with no code after it, treat it as an explanation (an "ask" answer, not code to inject)
  local thinking_content = extract_thinking_content(response)
  local is_explanation = false

  -- Clean the response (remove markdown, explanations, etc.)
  local filetype = vim.fn.fnamemodify(worker.event.target_path or "", ":e")
  local cleaned_response = clean_response(response, filetype)

  -- If cleaned response is empty/trivial but there was thinking content,
  -- this is an explanation — show it as-is instead of injecting
  if thinking_content and #thinking_content > 10 and (#cleaned_response < 10 or cleaned_response:match("^%s*$")) then
    is_explanation = true
    cleaned_response = thinking_content
  end

  local flog = require("codetyper.support.flog")
  flog.info("worker", string.format("raw_response_len=%d cleaned_len=%d is_explanation=%s type=%s", #(response or ""), #(cleaned_response or ""), tostring(is_explanation), type(cleaned_response)))
  flog.debug("worker", "cleaned_preview: " .. (cleaned_response and cleaned_response:sub(1, 300):gsub("\n", "\\n") or "nil"))

  -- Score confidence on cleaned response
  local conf_score, breakdown = confidence.score(cleaned_response, worker.event.prompt_content)

  worker.status = "completed"
  active_workers[worker.id] = nil

  pcall(function()
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
      type = "success",
      message = string.format(
        "Worker %s completed (%.2fs, confidence: %.2f - %s)",
        worker.id,
        duration,
        conf_score,
        confidence.level_name(conf_score)
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
    is_explanation = is_explanation,
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

  worker.status = "cancelled"
  active_workers[worker_id] = nil

  pcall(function()
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
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

return M
