local state = require("codetyper.state.state")
local logs = require("codetyper.adapters.nvim.ui.logs")
local queue = require("codetyper.core.events.queue")

--- Close the logs panel and clean up listeners, windows, buffers
---@param force? boolean Force close even if not marked as open
local function close(force)
  if not state.is_open and not force then
    return
  end

  if state.listener_id then
    pcall(logs.remove_listener, state.listener_id)
    state.listener_id = nil
  end

  if state.queue_listener_id then
    pcall(queue.remove_listener, state.queue_listener_id)
    state.queue_listener_id = nil
  end

  if state.queue_win then
    pcall(vim.api.nvim_win_close, state.queue_win, true)
    state.queue_win = nil
  end

  if state.win then
    pcall(vim.api.nvim_win_close, state.win, true)
    state.win = nil
  end

  if state.queue_buf then
    pcall(vim.api.nvim_buf_delete, state.queue_buf, { force = true })
    state.queue_buf = nil
  end

  if state.buf then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
    state.buf = nil
  end

  state.is_open = false
end

return close
