local state = require("codetyper.state.state")

--- Close the diff review UI
local function close()
  if not state.is_open then
    return
  end

  pcall(vim.cmd, "tabclose")

  state.list_buf = nil
  state.list_win = nil
  state.diff_buf = nil
  state.diff_win = nil
  state.is_open = false
end

return close
