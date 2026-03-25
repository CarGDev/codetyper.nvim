local utils = require("codetyper.support.utils")
local processed_prompts = require("codetyper.constants.constants").processed_prompts
local is_processing = require("codetyper.constants.constants").is_processing
local get_prompt_key = require("codetyper.adapters.nvim.autocmds.get_prompt_key")
local read_attached_files = require("codetyper.adapters.nvim.autocmds.read_attached_files")
local create_injection_marks = require("codetyper.adapters.nvim.autocmds.create_injection_marks")
local get_config = require("codetyper.utils.get_config").get_config

--- Check if the buffer has a newly closed prompt and auto-process
local function check_for_closed_prompt()
  if is_processing then
    return
  end
  is_processing = true

  local has_closing_tag = require("codetyper.parser.has_closing_tag")
  local get_last_prompt = require("codetyper.parser.get_last_prompt")
  local clean_prompt = require("codetyper.parser.clean_prompt")
  local strip_file_references = require("codetyper.parser.strip_file_references")

  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" then
    is_processing = false
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)

  if #lines == 0 then
    is_processing = false
    return
  end

  local current_line = lines[1]

  local cfg = get_config()
  if has_closing_tag(current_line, cfg.patterns.close_tag) then
    local prompt = get_last_prompt(bufnr)
    if prompt and prompt.content and prompt.content ~= "" then
      local prompt_key = get_prompt_key(bufnr, prompt)

      if processed_prompts[prompt_key] then
        is_processing = false
        return
      end

      processed_prompts[prompt_key] = true

      local codetyper = require("codetyper")
      local ct_config = codetyper.get_config()
      local scheduler_enabled = ct_config and ct_config.scheduler and ct_config.scheduler.enabled

      if scheduler_enabled then
        vim.schedule(function()
          local queue = require("codetyper.core.events.queue")
          local patch_mod = require("codetyper.core.diff.patch")
          local intent_mod = require("codetyper.core.intent")
          local scope_mod = require("codetyper.core.scope")

          local snapshot = patch_mod.snapshot_buffer(bufnr, {
            start_line = prompt.start_line,
            end_line = prompt.end_line,
          })

          local target_path
          if utils.is_coder_file(current_file) then
            target_path = utils.get_target_path(current_file)
          else
            target_path = current_file
          end

          local attached_files = read_attached_files(prompt.content, current_file)

          local cleaned = clean_prompt(strip_file_references(prompt.content))

          local is_from_coder_file = utils.is_coder_file(current_file)

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

          if not is_from_coder_file and scope and (scope.type == "function" or scope.type == "method") then
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
            scope = scope,
            scope_text = scope_text,
            scope_range = scope_range,
            attached_files = attached_files,
            injection_marks = injection_marks,
          })

          local scope_info = scope
              and scope.type ~= "file"
              and string.format(" [%s: %s]", scope.type, scope.name or "anonymous")
            or ""
          utils.notify(string.format("Prompt queued: %s%s", intent.type, scope_info), vim.log.levels.INFO)
        end)
      else
        utils.notify("Processing prompt...", vim.log.levels.INFO)
        vim.schedule(function()
          vim.cmd("CoderProcess")
        end)
      end
    end
  end
  is_processing = false
end

return check_for_closed_prompt
