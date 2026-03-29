local utils = require("codetyper.support.utils")
local processed_prompts = require("codetyper.constants.constants").processed_prompts
local get_prompt_key = require("codetyper.adapters.nvim.autocmds.get_prompt_key")
local read_attached_files = require("codetyper.adapters.nvim.autocmds.read_attached_files")
local create_injection_marks = require("codetyper.adapters.nvim.autocmds.create_injection_marks")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Process a single prompt through the scheduler
---@param bufnr number Buffer number
---@param prompt table Prompt object with start_line, end_line, content
---@param current_file string Current file path
---@param skip_processed_check? boolean Skip the processed check (for manual mode)
local function process_single_prompt(bufnr, prompt, current_file, skip_processed_check)
  flog.info("process_single_prompt", ">>> ENTERED") -- TODO: remove after debugging
  local clean_prompt = require("codetyper.parser.clean_prompt")
  local strip_file_references = require("codetyper.parser.strip_file_references")
  local scheduler = require("codetyper.core.scheduler.scheduler")

  if not prompt.content or prompt.content == "" then
    flog.warn("process_single_prompt", "empty prompt, aborting") -- TODO: remove after debugging
    return
  end

  flog.info("process_single_prompt", string.format( -- TODO: remove after debugging
    "prompt_lines=%d-%d file=%s skip_check=%s",
    prompt.start_line or 0, prompt.end_line or 0,
    current_file or "nil", tostring(skip_processed_check)
  ))
  flog.debug("process_single_prompt", "content_preview: " .. (prompt.content or ""):sub(1, 100):gsub("\n", "\\n"))

  if not scheduler.status().running then
    flog.info("process_single_prompt", "starting scheduler") -- TODO: remove after debugging
    scheduler.start()
  end

  local prompt_key = get_prompt_key(bufnr, prompt)

  if not skip_processed_check and processed_prompts[prompt_key] then
    flog.warn("process_single_prompt", "already processed, skipping") -- TODO: remove after debugging
    return
  end

  processed_prompts[prompt_key] = true

  vim.schedule(function()
    flog.info("process_single_prompt", ">>> vim.schedule callback ENTERED") -- TODO: remove after debugging
    local queue = require("codetyper.core.events.queue")
    local patch_mod = require("codetyper.core.diff.patch")
    local intent_mod = require("codetyper.core.intent")
    local scope_mod = require("codetyper.core.scope")

    local snapshot = patch_mod.snapshot_buffer(bufnr, {
      start_line = prompt.start_line,
      end_line = prompt.end_line,
    })

    local target_path
    local is_from_coder_file = utils.is_coder_file(current_file)
    if is_from_coder_file then
      target_path = utils.get_target_path(current_file)
    else
      target_path = current_file
    end

    local attached_files = read_attached_files(prompt.content, current_file)

    local cleaned = clean_prompt(strip_file_references(prompt.content))

    flog.info("process_single_prompt", string.format( -- TODO: remove after debugging
      "target=%s is_coder_file=%s cleaned_len=%d",
      target_path or "nil", tostring(is_from_coder_file), #cleaned
    ))

    local target_bufnr = vim.fn.bufnr(target_path)
    local scope = nil
    local scope_text = nil
    local scope_range = nil

    if not is_from_coder_file then
      if target_bufnr == -1 then
        target_bufnr = bufnr
      end
      scope = scope_mod.resolve_scope(target_bufnr, prompt.start_line, 1)
      if scope and scope.type ~= "file" then
        scope_text = scope.text
        scope_range = {
          start_line = scope.range.start_row,
          end_line = scope.range.end_row,
        }
      end
    else
      if target_bufnr == -1 then
        target_bufnr = vim.fn.bufadd(target_path)
        if target_bufnr ~= 0 then
          vim.fn.bufload(target_bufnr)
        end
      end
    end

    local intent = intent_mod.detect(cleaned)

    if prompt.intent_override then
      intent.action = prompt.intent_override.action or intent.action
      if prompt.intent_override.type then
        intent.type = prompt.intent_override.type
      end
    elseif not is_from_coder_file and scope and (scope.type == "function" or scope.type == "method") then
      if intent.type == "add" or intent.action == "insert" or intent.action == "append" then
        intent = {
          type = "complete",
          scope_hint = "function",
          confidence = intent.confidence,
          action = "replace",
          keywords = intent.keywords,
        }
      end
    end

    if is_from_coder_file and (intent.action == "replace" or intent.type == "complete") then
      intent = {
        type = intent.type == "complete" and "add" or intent.type,
        confidence = intent.confidence,
        action = "append",
        keywords = intent.keywords,
      }
    end

    flog.info("process_single_prompt", string.format( -- TODO: remove after debugging
      "intent: type=%s action=%s scope=%s scope_range=%s",
      intent.type or "nil", intent.action or "nil",
      scope and scope.type or "nil",
      scope_range and (scope_range.start_line .. "-" .. scope_range.end_line) or "nil"
    ))

    local project_context = nil
    if prompt.is_whole_file then
      pcall(function()
        local tree = require("codetyper.support.tree")
        local tree_log = tree.get_tree_log_path()
        if tree_log and vim.fn.filereadable(tree_log) == 1 then
          local tree_lines = vim.fn.readfile(tree_log)
          if tree_lines and #tree_lines > 0 then
            local tree_content = table.concat(tree_lines, "\n")
            project_context = tree_content:sub(1, 4000)
          end
        end
      end)
    end

    local priority = 2
    if intent.type == "fix" or intent.type == "complete" then
      priority = 1
    elseif intent.type == "test" or intent.type == "document" then
      priority = 3
    end

    local raw_start = (prompt.injection_range and prompt.injection_range.start_line) or prompt.start_line or 1
    local raw_end = (prompt.injection_range and prompt.injection_range.end_line) or prompt.end_line or 1
    local target_line_count = vim.api.nvim_buf_line_count(target_bufnr)
    target_line_count = math.max(1, target_line_count)
    local range_start = math.max(1, math.min(raw_start, target_line_count))
    local range_end = math.max(1, math.min(raw_end, target_line_count))
    if range_end < range_start then
      range_end = range_start
    end
    local event_range = { start_line = range_start, end_line = range_end }

    local range_for_marks = scope_range or event_range
    local injection_marks = create_injection_marks(target_bufnr, range_for_marks)

    flog.info("process_single_prompt", string.format( -- TODO: remove after debugging
      "enqueueing: event_range=%d-%d marks_range=%d-%d has_marks=%s injection_range=%s priority=%d",
      range_start, range_end,
      range_for_marks.start_line, range_for_marks.end_line,
      injection_marks and "yes" or "NO",
      prompt.injection_range and (prompt.injection_range.start_line .. "-" .. prompt.injection_range.end_line) or "nil",
      priority
    ))

    queue.enqueue({
      id = queue.generate_id(),
      bufnr = bufnr,
      range = event_range,
      timestamp = os.clock(),
      changedtick = snapshot.changedtick,
      content_hash = snapshot.content_hash,
      prompt_content = cleaned,
      target_path = target_path,
      priority = priority,
      status = "pending",
      attempt_count = 0,
      intent = intent,
      intent_override = prompt.intent_override,
      scope = scope,
      scope_text = scope_text,
      scope_range = scope_range,
      attached_files = attached_files,
      injection_marks = injection_marks,
      injection_range = prompt.injection_range,
      is_whole_file = prompt.is_whole_file,
      project_context = project_context,
    })

    flog.info("process_single_prompt", ">>> event enqueued successfully") -- TODO: remove after debugging

    local scope_info = scope
        and scope.type ~= "file"
        and string.format(" [%s: %s]", scope.type, scope.name or "anonymous")
      or ""
    utils.notify(string.format("Prompt queued: %s%s", intent.type, scope_info), vim.log.levels.INFO)
  end)
end

return process_single_prompt
