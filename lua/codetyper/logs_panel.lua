---@mod codetyper.logs_panel Standalone logs panel for code generation
---
--- Shows real-time logs when generating code via /@ @/ prompts.

local M = {}

local logs = require("codetyper.agent.logs")
local queue = require("codetyper.agent.queue")

---@class LogsPanelState
---@field buf number|nil Logs buffer
---@field win number|nil Logs window
---@field queue_buf number|nil Queue buffer
---@field queue_win number|nil Queue window
---@field is_open boolean Whether the panel is open
---@field listener_id number|nil Listener ID for logs
---@field queue_listener_id number|nil Listener ID for queue

local state = {
  buf = nil,
  win = nil,
  queue_buf = nil,
  queue_win = nil,
  is_open = false,
  listener_id = nil,
  queue_listener_id = nil,
}

--- Namespace for highlights
local ns_logs = vim.api.nvim_create_namespace("codetyper_logs_panel")
local ns_queue = vim.api.nvim_create_namespace("codetyper_queue_panel")

--- Fixed dimensions
local LOGS_WIDTH = 60
local QUEUE_HEIGHT = 8

--- Add a log entry to the buffer
---@param entry table Log entry
local function add_log_entry(entry)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end

    -- Handle clear event
    if entry.level == "clear" then
      vim.bo[state.buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
        "Generation Logs",
        string.rep("─", LOGS_WIDTH - 2),
        "",
      })
      vim.bo[state.buf].modifiable = false
      return
    end

    vim.bo[state.buf].modifiable = true

    local formatted = logs.format_entry(entry)
    local formatted_lines = vim.split(formatted, "\n", { plain = true })
    local line_count = vim.api.nvim_buf_line_count(state.buf)

    vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, formatted_lines)

    -- Apply highlighting based on level
    local hl_map = {
      info = "DiagnosticInfo",
      debug = "Comment",
      request = "DiagnosticWarn",
      response = "DiagnosticOk",
      tool = "DiagnosticHint",
      error = "DiagnosticError",
    }

    local hl = hl_map[entry.level] or "Normal"
    for i = 0, #formatted_lines - 1 do
      vim.api.nvim_buf_add_highlight(state.buf, ns_logs, hl, line_count + i, 0, -1)
    end

    vim.bo[state.buf].modifiable = false

    -- Auto-scroll logs
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local new_count = vim.api.nvim_buf_line_count(state.buf)
      pcall(vim.api.nvim_win_set_cursor, state.win, { new_count, 0 })
    end
  end)
end

--- Update the title with token counts
local function update_title()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local prompt_tokens, response_tokens = logs.get_token_totals()
  local provider, model = logs.get_provider_info()

  if provider and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = true
    local title = string.format("%s | %d/%d tokens", (provider or ""):upper(), prompt_tokens, response_tokens)
    vim.api.nvim_buf_set_lines(state.buf, 0, 1, false, { title })
    vim.bo[state.buf].modifiable = false
  end
end

--- Update the queue display
local function update_queue_display()
  if not state.queue_buf or not vim.api.nvim_buf_is_valid(state.queue_buf) then
    return
  end

  vim.schedule(function()
    if not state.queue_buf or not vim.api.nvim_buf_is_valid(state.queue_buf) then
      return
    end

    vim.bo[state.queue_buf].modifiable = true

    local lines = {
      "Queue",
      string.rep("─", LOGS_WIDTH - 2),
    }

    -- Get all events (pending and processing)
    local pending = queue.get_pending()
    local processing = queue.get_processing()

    -- Add processing events first
    for _, event in ipairs(processing) do
      local filename = vim.fn.fnamemodify(event.target_path or "", ":t")
      local line_num = event.range and event.range.start_line or 0
      local prompt_preview = (event.prompt_content or ""):sub(1, 25):gsub("\n", " ")
      if #(event.prompt_content or "") > 25 then
        prompt_preview = prompt_preview .. "..."
      end
      table.insert(lines, string.format("▶ %s:%d %s", filename, line_num, prompt_preview))
    end

    -- Add pending events
    for _, event in ipairs(pending) do
      local filename = vim.fn.fnamemodify(event.target_path or "", ":t")
      local line_num = event.range and event.range.start_line or 0
      local prompt_preview = (event.prompt_content or ""):sub(1, 25):gsub("\n", " ")
      if #(event.prompt_content or "") > 25 then
        prompt_preview = prompt_preview .. "..."
      end
      table.insert(lines, string.format("○ %s:%d %s", filename, line_num, prompt_preview))
    end

    if #pending == 0 and #processing == 0 then
      table.insert(lines, "  (empty)")
    end

    vim.api.nvim_buf_set_lines(state.queue_buf, 0, -1, false, lines)

    -- Apply highlights
    vim.api.nvim_buf_clear_namespace(state.queue_buf, ns_queue, 0, -1)
    vim.api.nvim_buf_add_highlight(state.queue_buf, ns_queue, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(state.queue_buf, ns_queue, "Comment", 1, 0, -1)

    local line_idx = 2
    for _ = 1, #processing do
      vim.api.nvim_buf_add_highlight(state.queue_buf, ns_queue, "DiagnosticWarn", line_idx, 0, 1)
      vim.api.nvim_buf_add_highlight(state.queue_buf, ns_queue, "String", line_idx, 2, -1)
      line_idx = line_idx + 1
    end
    for _ = 1, #pending do
      vim.api.nvim_buf_add_highlight(state.queue_buf, ns_queue, "Comment", line_idx, 0, 1)
      vim.api.nvim_buf_add_highlight(state.queue_buf, ns_queue, "Normal", line_idx, 2, -1)
      line_idx = line_idx + 1
    end

    vim.bo[state.queue_buf].modifiable = false
  end)
end

--- Open the logs panel
function M.open()
  if state.is_open then
    return
  end

  -- Clear previous logs
  logs.clear()

  -- Create logs buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].swapfile = false

  -- Create window on the right
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, LOGS_WIDTH)

  -- Window options for logs
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].winfixwidth = true
  vim.wo[state.win].cursorline = false

  -- Set initial content for logs
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
    "Generation Logs",
    string.rep("─", LOGS_WIDTH - 2),
    "",
  })
  vim.bo[state.buf].modifiable = false

  -- Create queue buffer
  state.queue_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.queue_buf].buftype = "nofile"
  vim.bo[state.queue_buf].bufhidden = "hide"
  vim.bo[state.queue_buf].swapfile = false

  -- Create queue window as horizontal split at bottom of logs window
  vim.cmd("belowright split")
  state.queue_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.queue_win, state.queue_buf)
  vim.api.nvim_win_set_height(state.queue_win, QUEUE_HEIGHT)

  -- Window options for queue
  vim.wo[state.queue_win].number = false
  vim.wo[state.queue_win].relativenumber = false
  vim.wo[state.queue_win].signcolumn = "no"
  vim.wo[state.queue_win].wrap = true
  vim.wo[state.queue_win].linebreak = true
  vim.wo[state.queue_win].winfixheight = true
  vim.wo[state.queue_win].cursorline = false

  -- Setup keymaps for logs buffer
  local opts = { buffer = state.buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  -- Setup keymaps for queue buffer
  local queue_opts = { buffer = state.queue_buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", M.close, queue_opts)
  vim.keymap.set("n", "<Esc>", M.close, queue_opts)

  -- Register log listener
  state.listener_id = logs.add_listener(function(entry)
    add_log_entry(entry)
    if entry.level == "response" then
      vim.schedule(update_title)
    end
  end)

  -- Register queue listener
  state.queue_listener_id = queue.add_listener(function()
    update_queue_display()
  end)

  -- Initial queue display
  update_queue_display()

  state.is_open = true

  -- Return focus to previous window
  vim.cmd("wincmd p")

  logs.info("Logs panel opened")
end

--- Close the logs panel
function M.close()
  if not state.is_open then
    return
  end

  -- Remove log listener
  if state.listener_id then
    logs.remove_listener(state.listener_id)
    state.listener_id = nil
  end

  -- Remove queue listener
  if state.queue_listener_id then
    queue.remove_listener(state.queue_listener_id)
    state.queue_listener_id = nil
  end

  -- Close queue window
  if state.queue_win and vim.api.nvim_win_is_valid(state.queue_win) then
    pcall(vim.api.nvim_win_close, state.queue_win, true)
  end

  -- Close logs window
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end

  -- Reset state
  state.buf = nil
  state.win = nil
  state.queue_buf = nil
  state.queue_win = nil
  state.is_open = false
end

--- Toggle the logs panel
function M.toggle()
  if state.is_open then
    M.close()
  else
    M.open()
  end
end

--- Check if panel is open
---@return boolean
function M.is_open()
  return state.is_open
end

--- Ensure panel is open (call before starting generation)
function M.ensure_open()
  if not state.is_open then
    M.open()
  end
end

return M
