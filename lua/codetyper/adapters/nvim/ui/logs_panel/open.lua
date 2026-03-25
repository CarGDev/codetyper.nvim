local state = require("codetyper.state.state")
local logs_clear = require("codetyper.adapters.nvim.ui.logs.clear")
local logs_add_listener = require("codetyper.adapters.nvim.ui.logs.add_listener")
local logs_info = require("codetyper.adapters.nvim.ui.logs.info")
local queue = require("codetyper.core.events.queue")
local constants = require("codetyper.adapters.nvim.ui.logs_panel.constants")
local add_log_entry = require("codetyper.adapters.nvim.ui.logs_panel.add_log_entry")
local update_title = require("codetyper.adapters.nvim.ui.logs_panel.update_title")
local update_queue_display = require("codetyper.adapters.nvim.ui.logs_panel.update_queue_display")
local close = require("codetyper.adapters.nvim.ui.logs_panel.close")

--- Open the logs panel with logs window and queue window
local function open()
  if state.is_open then
    return
  end

  logs_clear()

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].swapfile = false

  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, constants.LOGS_WIDTH)

  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].winfixwidth = true
  vim.wo[state.win].cursorline = false

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
    "Generation Logs",
    string.rep("─", constants.LOGS_WIDTH - 2),
    "",
  })
  vim.bo[state.buf].modifiable = false

  state.queue_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.queue_buf].buftype = "nofile"
  vim.bo[state.queue_buf].bufhidden = "hide"
  vim.bo[state.queue_buf].swapfile = false

  vim.cmd("belowright split")
  state.queue_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.queue_win, state.queue_buf)
  vim.api.nvim_win_set_height(state.queue_win, constants.QUEUE_HEIGHT)

  vim.wo[state.queue_win].number = false
  vim.wo[state.queue_win].relativenumber = false
  vim.wo[state.queue_win].signcolumn = "no"
  vim.wo[state.queue_win].wrap = true
  vim.wo[state.queue_win].linebreak = true
  vim.wo[state.queue_win].winfixheight = true
  vim.wo[state.queue_win].cursorline = false

  local logs_keymap_opts = { buffer = state.buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", close, logs_keymap_opts)
  vim.keymap.set("n", "<Esc>", close, logs_keymap_opts)

  local queue_keymap_opts = { buffer = state.queue_buf, noremap = true, silent = true }
  vim.keymap.set("n", "q", close, queue_keymap_opts)
  vim.keymap.set("n", "<Esc>", close, queue_keymap_opts)

  state.listener_id = logs_add_listener(function(entry)
    add_log_entry(entry)
    if entry.level == "response" then
      vim.schedule(update_title)
    end
  end)

  state.queue_listener_id = queue.add_listener(function()
    update_queue_display()
  end)

  update_queue_display()

  state.is_open = true

  vim.cmd("wincmd p")

  logs_info("Logs panel opened")
end

return open
