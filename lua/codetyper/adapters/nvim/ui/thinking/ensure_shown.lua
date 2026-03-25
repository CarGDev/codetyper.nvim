local state = require("codetyper.state.state")
local throbber_new = require("codetyper.adapters.nvim.ui.throbber.new")
local queue = require("codetyper.core.events.queue")
local status_window_config = require("codetyper.adapters.nvim.ui.thinking.status_window_config")
local update_display = require("codetyper.adapters.nvim.ui.thinking.update_display")
local check_and_hide = require("codetyper.adapters.nvim.ui.thinking.check_and_hide")
local active_count = require("codetyper.adapters.nvim.ui.thinking.active_count")

--- Ensure the thinking status window is shown and throbber is running.
--- Call when starting prompt processing.
local function ensure_shown()
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    return
  end

  state.buf_id = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf_id].buftype = "nofile"
  vim.bo[state.buf_id].bufhidden = "wipe"
  vim.bo[state.buf_id].swapfile = false

  local config = status_window_config()
  state.win_id = vim.api.nvim_open_win(state.buf_id, false, config)
  vim.wo[state.win_id].wrap = true
  vim.wo[state.win_id].number = false
  vim.wo[state.win_id].relativenumber = false

  state.throbber = throbber_new(function(icon)
    update_display(icon)
    if active_count() <= 0 then
      vim.defer_fn(check_and_hide, 300)
    end
  end)
  state.throbber:start()

  state.queue_listener_id = queue.add_listener(function(_, _, _)
    vim.schedule(function()
      if active_count() <= 0 then
        vim.defer_fn(check_and_hide, 400)
      end
    end)
  end)

  local initial_icon = (state.throbber and state.throbber.icon_set and state.throbber.icon_set[1]) or "⠋"
  update_display(initial_icon, true)
end

return ensure_shown
