---@mod codetyper.logs_panel Standalone logs panel for code generation
---
--- Shows real-time logs when generating code via /@ @/ prompts.

local M = {}

local logs = require("codetyper.agent.logs")

---@class LogsPanelState
---@field buf number|nil Buffer
---@field win number|nil Window
---@field is_open boolean Whether the panel is open
---@field listener_id number|nil Listener ID for logs

local state = {
  buf = nil,
  win = nil,
  is_open = false,
  listener_id = nil,
}

--- Namespace for highlights
local ns_logs = vim.api.nvim_create_namespace("codetyper_logs_panel")

--- Fixed width
local LOGS_WIDTH = 60

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
    local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local line_num = #lines

    vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { formatted })

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
    vim.api.nvim_buf_add_highlight(state.buf, ns_logs, hl, line_num, 0, -1)

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

--- Open the logs panel
function M.open()
  if state.is_open then
    return
  end

  -- Clear previous logs
  logs.clear()

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].swapfile = false

  -- Create window on the right
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, LOGS_WIDTH)

  -- Window options
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].winfixwidth = true
  vim.wo[state.win].cursorline = false

  -- Set initial content
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
    "Generation Logs",
    string.rep("─", LOGS_WIDTH - 2),
    "",
  })
  vim.bo[state.buf].modifiable = false

  -- Setup keymaps
  local opts = { buffer = state.buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  -- Register log listener
  state.listener_id = logs.add_listener(function(entry)
    add_log_entry(entry)
    if entry.level == "response" then
      vim.schedule(update_title)
    end
  end)

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

  -- Close window
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end

  -- Reset state
  state.buf = nil
  state.win = nil
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
