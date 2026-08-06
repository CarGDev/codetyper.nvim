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
---@field tool_calls table[]|nil Native tool calls from structured API response
---@field system_prompt string|nil System prompt used for the request (needed for agent loop)

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
  -- With closing tag
  local thinking = text:match("^%s*@thinking%s*\n(.-)\nend thinking")
  if thinking then
    return thinking:match("^%s*(.-)%s*$") or thinking
  end
  -- Without closing tag — entire response is thinking
  thinking = text:match("^%s*@thinking%s*\n(.*)")
  if thinking then
    return thinking:match("^%s*(.-)%s*$") or thinking
  end
  return nil
end

--- Strip @thinking ... end thinking block; return only the code part for injection.
--- Handles both closed (@thinking ... end thinking) and unclosed (@thinking ...) blocks.
---@param text string Raw response that may start with @thinking
---@return string Text with thinking block removed (or empty if no code after thinking)
local function strip_thinking_block(text)
  if not text or text == "" then
    return text or ""
  end
  -- With closing tag: strip thinking, keep everything after
  local after = text:match("^%s*@thinking[%s%S]*\nend thinking%s*\n(.*)")
  if after then
    return after:match("^%s*(.-)%s*$") or after
  end
  -- Without closing tag: the whole response is thinking — nothing to inject
  if text:match("^%s*@thinking") then
    return ""
  end
  return text
end

--- Clean LLM response to extract only code
---@param response string Raw LLM response
---@param filetype string|nil File type for language detection
---@return string Cleaned code
--- Detect whether a line looks like code based on structural signals.
--- Checks for syntax characters, indentation, and symbol density
--- rather than trying to enumerate English phrases.
---@param line string A trimmed line of text
---@return boolean
local function is_code_line(line)
  -- Empty or very short lines are ambiguous — treat as code to avoid
  -- stripping blank separators inside code blocks
  if #line < 3 then
    return true
  end

  -- Structural code characters: braces, parens, semicolons, arrows, operators
  if line:match("[{}%(%)%[%];=<>]") then
    return true
  end

  -- Common code starters: keywords, decorators, imports, comments
  if line:match("^%s*[%-%+%*/#@]")          -- comment / decorator / diff marker
    or line:match("^%s*import%s")
    or line:match("^%s*export%s")
    or line:match("^%s*from%s")
    or line:match("^%s*require%s*%(")
    or line:match("^%s*local%s")
    or line:match("^%s*const%s")
    or line:match("^%s*let%s")
    or line:match("^%s*var%s")
    or line:match("^%s*function%s")
    or line:match("^%s*return%s")
    or line:match("^%s*if%s")
    or line:match("^%s*for%s")
    or line:match("^%s*while%s")
    or line:match("^%s*class%s")
    or line:match("^%s*interface%s")
    or line:match("^%s*type%s")
    or line:match("^%s*enum%s")
    or line:match("^%s*def%s")
    or line:match("^%s*async%s")
    or line:match("^%s*await%s")
    or line:match("^%s*end$")
    or line:match("^%s*end[%s%-]")
  then
    return true
  end

  -- Indented lines (2+ spaces or tab) are almost always code
  if line:match("^%s%s") then
    return true
  end

  -- Symbol density: code has more punctuation relative to letters.
  -- Count code-like symbols vs word characters.
  local symbols = #(line:gsub("[%w%s]", ""))
  local ratio = symbols / #line
  if ratio > 0.15 then
    return true
  end

  -- If none of the above matched, it's likely prose
  return false
end

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
    -- No code block found — strip prose that wraps code.
    -- Instead of listing English phrases, detect code structurally:
    -- a line is "code" if it has code-specific characters or patterns.
    -- Everything else before/after the code block is prose.
    local lines = vim.split(cleaned, "\n")

    -- Strip leading prose
    local code_start = 1
    for i, line in ipairs(lines) do
      local trimmed = line:match("^%s*(.-)%s*$") or ""
      if trimmed == "" then
        code_start = i + 1
      elseif not is_code_line(trimmed) then
        code_start = i + 1
      else
        break
      end
    end

    -- Strip trailing prose
    local code_end = #lines
    for i = #lines, code_start, -1 do
      local trimmed = lines[i]:match("^%s*(.-)%s*$") or ""
      if trimmed == "" then
        code_end = i - 1
      elseif not is_code_line(trimmed) then
        code_end = i - 1
      else
        break
      end
    end

    if code_start <= code_end then
      -- Also detect prose in the MIDDLE of code — this means the model
      -- output multiple code blocks with explanation between them.
      -- Truncate at the first interior prose line (keep only the first block).
      local cut_at = nil
      local consecutive_prose = 0
      for i = code_start, code_end do
        local trimmed = lines[i]:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" and not is_code_line(trimmed) then
          consecutive_prose = consecutive_prose + 1
          if consecutive_prose >= 1 and not cut_at then
            cut_at = i - 1
          end
        else
          consecutive_prose = 0
        end
      end

      local actual_end = cut_at or code_end
      local code_lines = {}
      for i = code_start, actual_end do
        table.insert(code_lines, lines[i])
      end
      cleaned = table.concat(code_lines, "\n")
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
    is_whole_file = event.is_whole_file,
    is_project_task = event.is_project_task,
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

    -- Prefer structured (streaming + native tools) when available
    if client.generate_structured then
      flog.info("worker", "using generate_structured (streaming + native tools)")
      -- Store system_prompt for the agent loop (it needs it for follow-up turns)
      worker._system_prompt = context.system_prompt or ""
      local received_chars = 0
      client.generate_structured(prompt, context, {
        on_text_delta = function(delta)
          if delta and #delta > 0 then
            received_chars = received_chars + #delta
            local size
            if received_chars >= 1000 then
              size = string.format("%.1fK", received_chars / 1000)
            else
              size = tostring(received_chars)
            end
            notify_stage(eid, "Receiving... (" .. size .. " chars)")
          end
        end,
        on_complete = function(result)
          if worker.status ~= "running" then return end
          M.complete_structured(worker, result)
        end,
        on_error = function(stream_err)
          if worker.status ~= "running" then return end
          handle_response(nil, stream_err)
        end,
      })
    else
      client.generate(prompt, context, handle_response)
    end
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
  flog.info("worker", string.format(
    "raw_response_len=%d cleaned_len=%d is_explanation=%s thinking=%s type=%s",
    #(response or ""), #(cleaned_response or ""),
    tostring(is_explanation),
    thinking_content and string.format("yes(%d)", #thinking_content) or "no",
    type(cleaned_response)
  ))
  flog.debug("worker", "cleaned_preview: " .. (cleaned_response and cleaned_response:sub(1, 300):gsub("\n", "\\n") or "nil"))

  -- Score confidence on cleaned response
  local conf_score, breakdown = confidence.score(cleaned_response, worker.event.prompt_content)

  -- If the model produced a thinking block, it was "reasoning" about the task.
  -- The code that follows is more likely to be a plan/explanation than actual code.
  -- Penalize confidence so escalation or explain-mode kicks in more easily.
  if thinking_content and #thinking_content > 10 and not is_explanation then
    conf_score = conf_score * 0.7
    flog.debug("worker", string.format("confidence penalized for thinking response: %.2f", conf_score))
  end

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

--- Complete worker with structured result from generate_structured()
---@param worker Worker
---@param result table { text: string, tool_calls: table[], usage: table|nil, finish_reason: string|nil }
function M.complete_structured(worker, result)
  local duration = os.clock() - worker.start_time
  flog.info("worker", string.format(
    ">>> complete_structured: id=%s duration=%.2fs text_len=%d tool_calls=%d finish=%s",
    worker.id, duration, #(result.text or ""), #(result.tool_calls or {}), result.finish_reason or "nil"
  ))

  -- If model returned tool_calls, pass them through directly — the scheduler
  -- will route to the native agent loop. Skip confidence scoring since the
  -- model is still working (tool results will feed back).
  if result.tool_calls and #result.tool_calls > 0 then
    worker.status = "completed"
    active_workers[worker.id] = nil

    worker.callback({
      success = true,
      response = result.text,
      error = nil,
      tool_calls = result.tool_calls,
      system_prompt = worker._system_prompt,
      confidence = 1.0,
      confidence_breakdown = {},
      duration = duration,
      worker_type = worker.worker_type,
      usage = result.usage,
    })
    return
  end

  -- No tool calls — treat as regular text response.
  -- Run through clean_response + confidence like the existing path.
  local filetype = vim.fn.fnamemodify(worker.event.target_path or "", ":e")
  local cleaned_response = clean_response(result.text or "", filetype)
  local is_explanation = false

  -- Empty text = explanation or thinking-only
  if #(cleaned_response or "") < 10 or (cleaned_response or ""):match("^%s*$") then
    is_explanation = true
    if #(result.text or "") > 10 then
      cleaned_response = result.text
    end
  end

  flog.info("worker", string.format(
    "structured text: cleaned_len=%d is_explanation=%s",
    #(cleaned_response or ""), tostring(is_explanation)
  ))

  local conf_score, breakdown = confidence.score(cleaned_response or "", worker.event.prompt_content or "")

  worker.status = "completed"
  active_workers[worker.id] = nil

  worker.callback({
    success = true,
    response = cleaned_response,
    error = nil,
    is_explanation = is_explanation,
    confidence = conf_score,
    confidence_breakdown = breakdown,
    duration = duration,
    worker_type = worker.worker_type,
    usage = result.usage,
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
