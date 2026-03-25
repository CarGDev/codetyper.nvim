local state = require("codetyper.state.state")

--- Close the context modal and reset state
local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.original_event = nil
  state.callback = nil
  state.llm_response = nil
end

return close
