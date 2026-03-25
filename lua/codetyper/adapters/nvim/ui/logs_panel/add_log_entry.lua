local state = require("codetyper.state.state")
local logs = require("codetyper.adapters.nvim.ui.logs")
local constants = require("codetyper.adapters.nvim.ui.logs_panel.constants")

--- Add a log entry to the panel buffer with highlighting
---@param entry table Log entry
local function add_log_entry(entry)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.schedule(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end

    if entry.level == "clear" then
      vim.bo[state.buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
        "Generation Logs",
        string.rep("─", constants.LOGS_WIDTH - 2),
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

    local highlight_map = {
      info = "DiagnosticInfo",
      debug = "Comment",
      request = "DiagnosticWarn",
      response = "DiagnosticOk",
      tool = "DiagnosticHint",
      error = "DiagnosticError",
    }

    local highlight_group = highlight_map[entry.level] or "Normal"
    for line_offset = 0, #formatted_lines - 1 do
      vim.api.nvim_buf_add_highlight(state.buf, constants.ns_logs, highlight_group, line_count + line_offset, 0, -1)
    end

    vim.bo[state.buf].modifiable = false

    if state.win and vim.api.nvim_win_is_valid(state.win) then
      local new_line_count = vim.api.nvim_buf_line_count(state.buf)
      pcall(vim.api.nvim_win_set_cursor, state.win, { new_line_count, 0 })
    end
  end)
end

return add_log_entry
