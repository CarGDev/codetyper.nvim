--- Explain window — interactive ask panel with conversation history
local M = {}

local flog = require("codetyper.support.flog")

--- Active explain window state
local state = {
  -- Conversation display (top, read-only markdown)
  chat_buf = nil,
  chat_win = nil,
  -- Input area (bottom, editable)
  input_buf = nil,
  input_win = nil,
  -- Loading animation
  loading_timer = nil,
  loading_dots = 0,
  -- Conversation history for follow-ups
  history = {},
  -- LLM context from the initial question
  llm_context = nil,
  -- File picker state
  picker_open = false,
}

--- Stop the loading animation
local function stop_loading()
  if state.loading_timer then
    state.loading_timer:stop()
    state.loading_timer = nil
  end
end

--- Append text to the chat buffer
---@param text string|string[] Markdown text (or list of lines) to append
local function append_to_chat(text)
  if not state.chat_buf or not vim.api.nvim_buf_is_valid(state.chat_buf) then
    return
  end
  local raw = type(text) == "table" and text or { text }
  -- Flatten: each element may contain newlines, nvim_buf_set_lines needs single lines
  local lines = {}
  for _, chunk in ipairs(raw) do
    for _, l in ipairs(vim.split(chunk, "\n", { plain = true })) do
      lines[#lines + 1] = l
    end
  end
  vim.bo[state.chat_buf].modifiable = true
  local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
  -- If buffer has just the initial empty line, replace it
  local first_line = vim.api.nvim_buf_get_lines(state.chat_buf, 0, 1, false)[1]
  if line_count == 1 and first_line == "" then
    vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, lines)
  else
    vim.api.nvim_buf_set_lines(state.chat_buf, line_count, line_count, false, lines)
  end
  vim.bo[state.chat_buf].modifiable = false

  -- Scroll chat to bottom
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    local new_count = vim.api.nvim_buf_line_count(state.chat_buf)
    vim.api.nvim_win_set_cursor(state.chat_win, { new_count, 0 })
  end
end

--- Replace all chat buffer content
---@param text string
local function set_chat_content(text)
  if not state.chat_buf or not vim.api.nvim_buf_is_valid(state.chat_buf) then
    return
  end
  local lines = vim.split(text, "\n", { plain = true })
  vim.bo[state.chat_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, lines)
  vim.bo[state.chat_buf].modifiable = false
end

--- Start the loading animation — appends "Thinking..." to chat
local function start_loading()
  stop_loading()
  state.loading_dots = 0
  -- Append a thinking indicator
  append_to_chat({ "", "---", "", "*Thinking...*" })
  local thinking_start = vim.api.nvim_buf_line_count(state.chat_buf)

  state.loading_timer = vim.loop.new_timer()
  state.loading_timer:start(400, 400, vim.schedule_wrap(function()
    if not state.chat_buf or not vim.api.nvim_buf_is_valid(state.chat_buf) then
      stop_loading()
      return
    end
    state.loading_dots = (state.loading_dots % 3) + 1
    local dots = string.rep(".", state.loading_dots)
    vim.bo[state.chat_buf].modifiable = true
    vim.api.nvim_buf_set_lines(
      state.chat_buf, thinking_start - 1, thinking_start, false,
      { "*Thinking" .. dots .. "*" }
    )
    vim.bo[state.chat_buf].modifiable = false
  end))
end

--- Remove the "Thinking..." indicator line from chat
local function remove_thinking_indicator()
  if not state.chat_buf or not vim.api.nvim_buf_is_valid(state.chat_buf) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
  -- Remove the last 3 lines (---, empty, Thinking...)
  if line_count >= 3 then
    local lines = vim.api.nvim_buf_get_lines(state.chat_buf, line_count - 3, line_count, false)
    if lines[1] == "---" and lines[2] == "" and (lines[3] or ""):match("^%*Thinking") then
      vim.bo[state.chat_buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.chat_buf, line_count - 3, line_count, false, {})
      vim.bo[state.chat_buf].modifiable = false
    end
  end
end

--- Build follow-up prompt with conversation history and attached files
---@param user_input string Raw user input (may contain @file refs)
---@return string prompt, table context
local function build_followup(user_input)
  local read_attached = require("codetyper.adapters.nvim.autocmds.read_attached_files")
  local strip_refs = require("codetyper.parser.strip_file_references")

  local base_path = (state.llm_context and state.llm_context.file_path) or vim.fn.expand("%:p")
  local attached = read_attached(user_input, base_path)
  local clean_input = strip_refs(user_input):gsub("^%s+", ""):gsub("%s+$", "")

  -- Build conversation context
  local parts = {}
  table.insert(parts, "This is a follow-up question in an ongoing conversation.")
  table.insert(parts, "")

  -- Always include original file and selection context
  local ctx = state.llm_context or {}
  if ctx.file_path then
    table.insert(parts, "**Original file:** `" .. ctx.file_path .. "`")
    if ctx.language then
      table.insert(parts, "**Language:** " .. ctx.language)
    end
  end
  if ctx.source_code and ctx.source_code ~= "" then
    local label = "Original code"
    if ctx.source_lines then
      label = string.format("Original code (lines %d-%d)", ctx.source_lines[1], ctx.source_lines[2])
    end
    table.insert(parts, string.format(
      "\n**%s:**\n```%s\n%s\n```",
      label, ctx.language or "", ctx.source_code
    ))
  end
  table.insert(parts, "")

  -- Include file dependency context (imports and importers)
  if ctx.deps_context then
    table.insert(parts, ctx.deps_context)
    table.insert(parts, "")
  end

  -- Include previous Q&A pairs (keep last 5 to avoid token bloat)
  local start_idx = math.max(1, #state.history - 9) -- pairs of 2
  for i = start_idx, #state.history do
    local entry = state.history[i]
    if entry.role == "user" then
      table.insert(parts, "**Previous question:** " .. entry.content)
    else
      table.insert(parts, "**Previous answer:** " .. entry.content:sub(1, 2000))
    end
    table.insert(parts, "")
  end

  -- Attach new referenced files from this follow-up
  if #attached > 0 then
    table.insert(parts, "**Referenced files:**")
    for _, f in ipairs(attached) do
      local ext = vim.fn.fnamemodify(f.path, ":e")
      table.insert(parts, string.format("\n`%s`:\n```%s\n%s\n```", f.path, ext, f.content))
    end
    table.insert(parts, "")
  end

  table.insert(parts, "**Current question:** " .. clean_input)

  local prompt = table.concat(parts, "\n")
  local context = vim.deepcopy(state.llm_context or {})
  context.prompt_type = "ask"

  return prompt, context
end

--- Send a follow-up question to the LLM
---@param user_input string
local function send_followup(user_input)
  if user_input == "" then
    return
  end

  -- Record user message
  table.insert(state.history, { role = "user", content = user_input })

  -- Show user question in chat
  append_to_chat({ "", "---", "", "**You:** " .. user_input })

  -- Show loading
  start_loading()

  -- Disable input while waiting
  if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
    vim.bo[state.input_buf].modifiable = false
  end

  local prompt, context = build_followup(user_input)
  local llm = require("codetyper.core.llm")

  llm.generate(prompt, context, function(response, err)
    vim.schedule(function()
      stop_loading()
      remove_thinking_indicator()

      -- Re-enable input
      if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
        vim.bo[state.input_buf].modifiable = true
      end

      if err then
        append_to_chat({ "", "**Error:** " .. tostring(err) })
        table.insert(state.history, { role = "assistant", content = "Error: " .. tostring(err) })
      elseif response then
        append_to_chat({ "", response })
        table.insert(state.history, { role = "assistant", content = response })
      else
        append_to_chat({ "", "*No response from LLM.*" })
      end

      -- Focus input and start insert
      if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
        vim.api.nvim_set_current_win(state.input_win)
      end
    end)
  end)
end

--- Submit the current input content
local function submit_input()
  if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
  local input = table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

  if input == "" then
    return
  end

  -- Clear input buffer
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  send_followup(input)
end

--- Open file picker for @ mentions in the input buffer
local function open_file_picker()
  if state.picker_open then
    return
  end

  -- Check for @@ (literal @)
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    local cursor = vim.api.nvim_win_get_cursor(state.input_win)
    local col = cursor[2]
    if col > 0 then
      local line = vim.api.nvim_buf_get_lines(state.input_buf, cursor[1] - 1, cursor[1], false)[1] or ""
      if line:sub(col, col) == "@" then
        vim.api.nvim_feedkeys("@", "n", false)
        return
      end
    end
  end

  -- Insert @ first
  vim.api.nvim_feedkeys("@", "n", false)

  vim.schedule(function()
    state.picker_open = true

    local project_root = vim.fn.getcwd()
    local ok_files, files = pcall(function()
      local raw = vim.fn.systemlist("find " .. vim.fn.shellescape(project_root)
        .. " -type f"
        .. " -not -path '*/node_modules/*'"
        .. " -not -path '*/.git/*'"
        .. " -not -path '*/.codetyper/*'"
        .. " -not -path '*/dist/*'"
        .. " -not -path '*/build/*'"
        .. " 2>/dev/null | head -200")
      local rel = {}
      for _, f in ipairs(raw) do
        local relative = f:sub(#project_root + 2)
        if relative ~= "" then
          table.insert(rel, relative)
        end
      end
      table.sort(rel)
      return rel
    end)

    if not ok_files or not files or #files == 0 then
      state.picker_open = false
      return
    end

    vim.ui.select(files, {
      prompt = "Attach file (@):",
      format_item = function(item) return item end,
    }, function(choice)
      state.picker_open = false

      if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
        return
      end

      -- Focus back to input window
      if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
        vim.api.nvim_set_current_win(state.input_win)
      end

      if not choice then
        return
      end

      -- Replace the @ with @filepath
      local cur = vim.api.nvim_win_get_cursor(state.input_win)
      local cur_row = cur[1]
      local cur_line = vim.api.nvim_buf_get_lines(state.input_buf, cur_row - 1, cur_row, false)[1] or ""

      local at_pos = cur_line:find("@[^@]*$")
      if at_pos then
        local before = cur_line:sub(1, at_pos - 1)
        local after = cur_line:sub(at_pos + 1):gsub("^%S*", "")
        local new_line = before .. "@" .. choice .. " " .. after
        vim.api.nvim_buf_set_lines(state.input_buf, cur_row - 1, cur_row, false, { new_line })
        vim.api.nvim_win_set_cursor(state.input_win, { cur_row, #before + #choice + 2 })
      end

      vim.cmd("startinsert")
    end)
  end)
end

--- Close the explain window (both panes)
function M.close()
  stop_loading()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_win_close(state.chat_win, true)
  end
  state.chat_win = nil
  state.chat_buf = nil
  state.input_win = nil
  state.input_buf = nil
  state.history = {}
  state.llm_context = nil
  state.picker_open = false
end

--- Show the interactive explain panel
---@param title string Window title
---@param content string Initial markdown content
---@param filetype string|nil Source filetype for context
---@param context table|nil LLM context to reuse for follow-ups
function M.show(title, content, filetype, context)
  flog.info("explain", "showing: " .. title:sub(1, 50))

  -- Close existing
  M.close()

  -- Store LLM context for follow-ups
  state.llm_context = context
  state.history = {}

  -- ── Chat buffer (top, read-only markdown) ──
  state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.chat_buf].buftype = "nofile"
  vim.bo[state.chat_buf].bufhidden = "wipe"
  vim.bo[state.chat_buf].swapfile = false
  vim.bo[state.chat_buf].filetype = "markdown"

  local is_loading = content:match("^Loading") or content:match("^Thinking")
  if is_loading then
    vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, { "# Thinking.", "", "Loading." })
    vim.bo[state.chat_buf].modifiable = false
  else
    local lines = vim.split(content, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, lines)
    vim.bo[state.chat_buf].modifiable = false
  end

  -- ── Layout: open chat panel only; input pane is added after first response ──
  local panel_width = math.max(40, math.floor(vim.o.columns * 0.4))

  -- Open chat panel as right vertical split
  vim.cmd("botright vsplit")
  state.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
  vim.api.nvim_win_set_width(state.chat_win, panel_width)

  -- Chat window options
  local chat_wo = {
    wrap = true, linebreak = true, number = false,
    relativenumber = false, signcolumn = "no",
    cursorline = false, spell = false,
    foldmethod = "manual", conceallevel = 2,
  }
  for k, v in pairs(chat_wo) do
    vim.wo[state.chat_win][k] = v
  end

  -- ── Keymaps for chat buffer ──
  local chat_opts = { buffer = state.chat_buf, silent = true }
  vim.keymap.set("n", "q", function() M.close() end, chat_opts)
  vim.keymap.set("n", "<Esc>", function() M.close() end, chat_opts)
  vim.keymap.set("n", "i", function()
    -- Jump to input pane on 'i' (only if it exists)
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
      vim.api.nvim_set_current_win(state.input_win)
      vim.cmd("startinsert")
    end
  end, chat_opts)

  -- Start loading animation if needed
  if is_loading then
    start_loading()
  end

  -- Return focus to the original window while loading
  vim.cmd("wincmd p")
end

--- Create the input pane below the chat window
local function create_input_pane()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    return -- already created
  end
  if not state.chat_win or not vim.api.nvim_win_is_valid(state.chat_win) then
    return
  end

  -- Focus chat window so the split opens inside the panel
  vim.api.nvim_set_current_win(state.chat_win)

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].swapfile = false
  vim.bo[state.input_buf].filetype = "markdown"

  -- Open input panel below chat (5 lines tall)
  vim.cmd("belowright split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
  vim.api.nvim_win_set_height(state.input_win, 5)

  -- Input window options
  vim.wo[state.input_win].wrap = true
  vim.wo[state.input_win].linebreak = true
  vim.wo[state.input_win].number = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn = "no"
  vim.wo[state.input_win].cursorline = true
  vim.wo[state.input_win].spell = false
  vim.wo[state.input_win].winhighlight = "Normal:Normal,CursorLine:Visual"

  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  -- ── Keymaps for input buffer ──
  local input_opts = { buffer = state.input_buf, silent = true }

  -- Submit: <CR> in normal mode, <C-CR> in insert mode
  vim.keymap.set("n", "<CR>", submit_input, input_opts)
  vim.keymap.set("i", "<C-CR>", function()
    vim.cmd("stopinsert")
    submit_input()
  end, input_opts)
  vim.keymap.set("i", "<C-Enter>", function()
    vim.cmd("stopinsert")
    submit_input()
  end, input_opts)

  -- Close
  vim.keymap.set("n", "q", function() M.close() end, input_opts)

  -- @ file picker
  vim.keymap.set("i", "@", open_file_picker, input_opts)

  -- Focus input and enter insert mode
  vim.cmd("startinsert")
end

--- Check if explain window is open
---@return boolean
function M.is_open()
  return state.chat_win ~= nil and vim.api.nvim_win_is_valid(state.chat_win)
end

--- Update content of the chat area (replaces all content)
---@param content string New markdown content
function M.update(content)
  stop_loading()
  set_chat_content(content)

  -- Record the initial response in history for follow-ups
  if #state.history == 0 then
    table.insert(state.history, { role = "assistant", content = content })
  end

  -- Create the input pane now that the first response has arrived
  create_input_pane()
end

--- Internal state for accumulating tool results
M._last_content = ""

return M
