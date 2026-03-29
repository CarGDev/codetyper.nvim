local M = {}

local EXPLAIN_PATTERNS = {
  "explain",
  "what does",
  "what is",
  "how does",
  "how is",
  "why does",
  "why is",
  "tell me",
  "walk through",
  "understand",
  "question",
  "what's this",
  "what this",
  "about this",
  "help me understand",
}

---@param input string
---@return boolean
local function is_explain_intent(input)
  local lower = input:lower()
  for _, pat in ipairs(EXPLAIN_PATTERNS) do
    if lower:find(pat, 1, true) then
      return true
    end
  end
  return false
end

--- Return editor dimensions (from UI, like 99 plugin)
---@return number width
---@return number height
local function get_ui_dimensions()
  local ui = vim.api.nvim_list_uis()[1]
  if ui then
    return ui.width, ui.height
  end
  return vim.o.columns, vim.o.lines
end

--- Centered floating window config for prompt (2/3 width, 1/3 height)
---@return table { width, height, row, col, border }
local function create_centered_window()
  local width, height = get_ui_dimensions()
  local win_width = math.floor(width * 2 / 3)
  local win_height = math.floor(height / 3)
  return {
    width = win_width,
    height = win_height,
    row = math.floor((height - win_height) / 2),
    col = math.floor((width - win_width) / 2),
    border = "rounded",
  }
end

--- Get visual selection text and range
---@return table|nil { text: string, start_line: number, end_line: number }
local function get_visual_selection()
  local mode = vim.api.nvim_get_mode().mode
  local is_visual = mode == "v" or mode == "V" or mode == "\22"

  -- Exit visual mode first so '< '> marks are set, then read the marks
  if is_visual then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end

  -- Read visual marks (set when leaving visual mode)
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")

  -- Marks are 0 if never set (no prior visual selection)
  if start_line <= 0 or end_line <= 0 then
    return nil
  end

  -- Only use marks if we were just in visual mode or marks look intentional
  -- (avoid stale marks from a previous unrelated selection)
  if not is_visual then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local text = table.concat(lines, "\n")

  return {
    text = text,
    start_line = start_line,
    end_line = end_line,
  }
end

--- Transform visual selection with custom prompt input
--- Opens input window for prompt, processes selection on confirm.
--- When nothing is selected (e.g. from Normal mode), only the prompt is requested.
function M.cmd_transform_selection()
  local logger = require("codetyper.support.logger")
  local flog = require("codetyper.support.flog") -- TODO: remove after debugging
  flog.info("transform", ">>> cmd_transform_selection ENTERED")
  logger.func_entry("commands", "cmd_transform_selection", {})
  -- Get visual selection (returns table with text, start_line, end_line or nil)
  local selection_data = get_visual_selection()
  local selection_text = selection_data and selection_data.text or ""
  local has_selection = selection_text and #selection_text >= 4

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.fn.expand("%:p")
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  line_count = math.max(1, line_count)

  flog.info("transform", string.format( -- TODO: remove after debugging
    "has_selection=%s sel_len=%d bufnr=%d file=%s",
    tostring(has_selection), #selection_text, bufnr, filepath
  ))

  -- Range for injection: selection, cursor line when no selection
  local start_line, end_line
  local is_cursor_insert = false
  if has_selection and selection_data then
    start_line = selection_data.start_line
    end_line = selection_data.end_line
    logger.info(
      "commands",
      string.format(
        "Visual selection: start=%d end=%d selected_text_lines=%d",
        start_line,
        end_line,
        #vim.split(selection_text, "\n", { plain = true })
      )
    )
  else
    -- No selection: insert at current cursor line (not replace whole file)
    start_line = vim.fn.line(".")
    end_line = start_line
    is_cursor_insert = true
  end
  -- Clamp to valid 1-based range (avoid 0 or out-of-bounds)
  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(1, math.min(end_line, line_count))
  if end_line < start_line then
    end_line = start_line
  end

  -- Capture injection range so we know exactly where to apply the generated code later
  local injection_range = { start_line = start_line, end_line = end_line }
  local range_line_count = end_line - start_line + 1

  -- Open centered prompt window (pattern from 99: acwrite + BufWriteCmd to submit, BufLeave to keep focus)
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype = "acwrite"
  vim.bo[prompt_buf].bufhidden = "wipe"
  vim.bo[prompt_buf].filetype = "markdown"
  vim.bo[prompt_buf].swapfile = false
  vim.api.nvim_buf_set_name(prompt_buf, "codetyper-prompt")

  -- Pre-fill prompt buffer with selected code context so user sees what they're editing
  local prefill_lines = {}
  if has_selection then
    table.insert(prefill_lines, "")
    table.insert(prefill_lines, string.format("[selected code lines %d-%d]", start_line, end_line))
    local sel_lines = vim.split(selection_text, "\n", { plain = true })
    for _, sl in ipairs(sel_lines) do
      table.insert(prefill_lines, sl)
    end
    table.insert(prefill_lines, "[/selected code]")
  end

  local win_opts = create_centered_window()
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    row = win_opts.row,
    col = win_opts.col,
    width = win_opts.width,
    height = win_opts.height,
    style = "minimal",
    border = win_opts.border,
    title = has_selection
        and string.format(" Prompt for lines %d-%d ", start_line, end_line)
      or " Enter prompt ",
    title_pos = "center",
  })
  vim.wo[prompt_win].wrap = true
  vim.api.nvim_set_current_win(prompt_win)

  -- Set prefilled content (cursor starts at line 1 for the user to type their prompt)
  if #prefill_lines > 0 then
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, prefill_lines)
    vim.api.nvim_win_set_cursor(prompt_win, { 1, 0 })
  end

  local function close_prompt()
    if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_win_close(prompt_win, true)
    end
    if prompt_buf and vim.api.nvim_buf_is_valid(prompt_buf) then
      vim.api.nvim_buf_delete(prompt_buf, { force = true })
    end
    prompt_win = nil
    prompt_buf = nil
  end

  local submitted = false

  -- Resolve enclosing context for the selection (handles all cases:
  -- partial inside function, whole function, spanning multiple functions, indentation fallback)
  local scope_mod = require("codetyper.core.scope")
  local sel_context = nil
  local is_whole_file = false

  -- Resolve enclosing scope for cursor position (even without selection)
  local cursor_scope = nil
  if is_cursor_insert then
    local scope_ok, cursor_resolved = pcall(scope_mod.resolve_scope, bufnr, start_line, 1)
    flog.info("transform", string.format( -- TODO: remove after debugging
      "resolve_scope: ok=%s type=%s name=%s",
      tostring(scope_ok),
      scope_ok and cursor_resolved and cursor_resolved.type or "nil",
      scope_ok and cursor_resolved and cursor_resolved.name or "nil"
    ))
    if scope_ok and cursor_resolved and cursor_resolved.type ~= "file" then
      cursor_scope = cursor_resolved
    end
  end

  if has_selection and selection_data then
    sel_context = scope_mod.resolve_selection_context(bufnr, start_line, end_line)
    is_whole_file = sel_context.type == "file"

    -- Expand injection range to cover full enclosing scopes when needed
    if sel_context.type == "whole_function" or sel_context.type == "multi_function" then
      injection_range.start_line = sel_context.expanded_start
      injection_range.end_line = sel_context.expanded_end
      start_line = sel_context.expanded_start
      end_line = sel_context.expanded_end
      -- Re-read the expanded selection text
      local exp_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
      selection_text = table.concat(exp_lines, "\n")
    end
  end

  local function submit_prompt()
    flog.info("transform", ">>> submit_prompt ENTERED") -- TODO: remove after debugging
    if not prompt_buf or not vim.api.nvim_buf_is_valid(prompt_buf) then
      flog.warn("transform", "prompt_buf invalid, aborting") -- TODO: remove after debugging
      close_prompt()
      return
    end
    submitted = true
    local lines_input = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
    -- Extract only the user's prompt (before the [selected code] block)
    local user_lines = {}
    for _, l in ipairs(lines_input) do
      if l:match("^%[selected code") then
        break
      end
      table.insert(user_lines, l)
    end
    local input = table.concat(user_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    flog.info("transform", "user_input: " .. input:sub(1, 200)) -- TODO: remove after debugging
    close_prompt()
    if input == "" then
      logger.info("commands", "User cancelled prompt input")
      return
    end

    local is_explain = is_explain_intent(input)

    -- Explain intent: show explanation in right-side panel (not injected into code)
    if is_explain then
      local ft = vim.bo[bufnr].filetype or "text"
      local code_to_explain = ""
      local context_block = ""

      if has_selection then
        code_to_explain = selection_text
        if sel_context and sel_context.type == "partial_function" and #sel_context.scopes > 0 then
          local scope = sel_context.scopes[1]
          context_block = string.format(
            '\n\nThis code is inside %s "%s":\n```%s\n%s\n```',
            scope.type, scope.name or "anonymous", ft, scope.text
          )
        end
      elseif cursor_scope then
        -- No selection but cursor inside a function — explain the function
        code_to_explain = cursor_scope.text or ""
        context_block = string.format(
          '\nThis is %s "%s" (lines %d-%d)',
          cursor_scope.type, cursor_scope.name or "anonymous",
          cursor_scope.range.start_row, cursor_scope.range.end_row
        )
      else
        -- No selection, no scope — explain the whole file
        code_to_explain = table.concat(
          vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"
        ):sub(1, 8000)
      end

      local explain_prompt = string.format(
        "%s\n\nExplain the following %s code in markdown format. "
          .. "Include: what it does, how it works, parameters, return values, "
          .. "usage examples if applicable, and any important details.%s"
          .. "\n\n```%s\n%s\n```",
        input, ft, context_block, ft, code_to_explain
      )

      flog.info("transform", "explain mode — sending to LLM") -- TODO: remove after debugging

      -- Send directly to LLM and show in explain window (bypass injection pipeline)
      local llm = require("codetyper.core.llm")
      local explain_window = require("codetyper.window.explain")

      explain_window.show("Thinking...", "Loading explanation...", ft)

      llm.generate(explain_prompt, {
        prompt_type = "ask",
        file_path = filepath,
        language = ft,
      }, function(response, err)
        vim.schedule(function()
          if err then
            explain_window.update("# Error\n\n" .. tostring(err))
          elseif response then
            local title = has_selection
                and string.format("Explanation (lines %d-%d)", start_line, end_line)
              or (cursor_scope and cursor_scope.name or filepath)
            explain_window.update("# " .. title .. "\n\n" .. response)
          else
            explain_window.update("# No Response\n\nThe LLM returned an empty response.")
          end
        end)
      end)
      return
    end

    local content
    local doc_injection_range = injection_range
    local doc_intent_override = has_selection and { action = "replace" }
      or (is_cursor_insert and { action = "insert" } or nil)

    if has_selection and sel_context then
      if sel_context.type == "partial_function" and #sel_context.scopes > 0 then
        local scope = sel_context.scopes[1]
        content = string.format(
          '%s\n\nEnclosing %s "%s" (lines %d-%d):\n```\n%s\n```\n\nSelected code to modify (lines %d-%d):\n%s',
          input,
          scope.type,
          scope.name or "anonymous",
          scope.range.start_row,
          scope.range.end_row,
          scope.text,
          start_line,
          end_line,
          selection_text
        )
      elseif sel_context.type == "multi_function" and #sel_context.scopes > 0 then
        local scope_descs = {}
        for _, s in ipairs(sel_context.scopes) do
          table.insert(
            scope_descs,
            string.format('- %s "%s" (lines %d-%d)', s.type, s.name or "anonymous", s.range.start_row, s.range.end_row)
          )
        end
        content = string.format(
          "%s\n\nAffected scopes:\n%s\n\nCode to replace (lines %d-%d):\n%s",
          input,
          table.concat(scope_descs, "\n"),
          start_line,
          end_line,
          selection_text
        )
      elseif sel_context.type == "indent_block" and #sel_context.scopes > 0 then
        local block = sel_context.scopes[1]
        content = string.format(
          "%s\n\nEnclosing block (lines %d-%d):\n```\n%s\n```\n\nSelected code to modify (lines %d-%d):\n%s",
          input,
          block.range.start_row,
          block.range.end_row,
          block.text,
          start_line,
          end_line,
          selection_text
        )
      else
        content = input .. "\n\nCode to replace (replace this code):\n" .. selection_text
      end
    elseif is_cursor_insert and cursor_scope then
      -- Cursor is inside a function — include function context so the LLM
      -- knows where the code will be inserted and can match style/variables.
      local ft = vim.bo[bufnr].filetype or "text"
      content = string.format(
        '%s\n\nYou are inside %s "%s" (lines %d-%d). Insert code at line %d.\n\n'
          .. "Enclosing function:\n```%s\n%s\n```\n\n"
          .. "Output ONLY the new code to insert. Do NOT repeat the existing function.",
        input,
        cursor_scope.type,
        cursor_scope.name or "anonymous",
        cursor_scope.range.start_row,
        cursor_scope.range.end_row,
        start_line,
        ft,
        cursor_scope.text
      )
    elseif is_cursor_insert then
      content = "Insert at line " .. start_line .. ":\n" .. input
    else
      content = input
    end

    local prompt = {
      content = content,
      start_line = doc_injection_range.start_line,
      end_line = doc_injection_range.end_line,
      start_col = 1,
      end_col = 1,
      user_prompt = input,
      injection_range = doc_injection_range,
      intent_override = doc_intent_override,
      is_whole_file = is_whole_file,
    }

    local flog = require("codetyper.support.flog")
    flog.info("transform", string.format(
      "submit: bufnr=%d file=%s range=%d-%d intent_override=%s is_whole_file=%s has_selection=%s",
      bufnr, filepath,
      doc_injection_range.start_line, doc_injection_range.end_line,
      doc_intent_override and doc_intent_override.action or "nil",
      tostring(is_whole_file), tostring(has_selection)
    ))
    flog.debug("transform", "prompt_content: " .. content:sub(1, 300):gsub("\n", "\\n"))

    local process_single_prompt = require("codetyper.adapters.nvim.autocmds.process_single_prompt")
    process_single_prompt(bufnr, prompt, filepath, true)
  end

  local augroup = vim.api.nvim_create_augroup("CodetyperPrompt_" .. prompt_buf, { clear = true })

  -- Submit on :w (acwrite buffer triggers BufWriteCmd)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = augroup,
    buffer = prompt_buf,
    callback = function()
      if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
        submitted = true
        submit_prompt()
      end
    end,
  })

  -- Keep focus in prompt window (prevent leaving to other buffers)
  vim.api.nvim_create_autocmd("BufLeave", {
    group = augroup,
    buffer = prompt_buf,
    callback = function()
      if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
        vim.api.nvim_set_current_win(prompt_win)
      end
    end,
  })

  -- Clean up when window is closed (e.g. :q or close button)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(prompt_win),
    callback = function()
      if not submitted then
        logger.info("commands", "User cancelled prompt input")
      end
      close_prompt()
    end,
  })

  local map_opts = { buffer = prompt_buf, noremap = true, silent = true }
  -- Normal mode: Enter, :w, or Ctrl+Enter to submit
  vim.keymap.set("n", "<CR>", submit_prompt, map_opts)
  vim.keymap.set("n", "<C-CR>", submit_prompt, map_opts)
  vim.keymap.set("n", "<C-Enter>", submit_prompt, map_opts)
  vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", vim.tbl_extend("force", map_opts, { desc = "Submit prompt" }))
  -- Insert mode: Ctrl+Enter to submit
  vim.keymap.set("i", "<C-CR>", submit_prompt, map_opts)
  vim.keymap.set("i", "<C-Enter>", submit_prompt, map_opts)
  -- Close/cancel: Esc (in normal), q, or :q
  vim.keymap.set("n", "<Esc>", close_prompt, map_opts)
  vim.keymap.set("n", "q", close_prompt, map_opts)

  vim.cmd("startinsert")
end

return M
