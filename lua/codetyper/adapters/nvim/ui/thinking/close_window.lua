local state = require("codetyper.state.state")
local queue = require("codetyper.core.events.queue")

--- Tear down the thinking window, throbber, timer, and queue listener
local function close_window()
  if state.timer then
    pcall(vim.fn.timer_stop, state.timer)
    state.timer = nil
  end
  if state.throbber then
    state.throbber:stop()
    state.throbber = nil
  end
  if state.queue_listener_id then
    queue.remove_listener(state.queue_listener_id)
    state.queue_listener_id = nil
  end
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    vim.api.nvim_win_close(state.win_id, true)
  end
  if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
    vim.api.nvim_buf_delete(state.buf_id, { force = true })
  end
  state.win_id = nil
  state.buf_id = nil
end

return close_window
