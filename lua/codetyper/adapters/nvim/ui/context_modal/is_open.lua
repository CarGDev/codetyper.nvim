local state = require("codetyper.state.state")

--- Check if the context modal is currently open
---@return boolean
local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return is_open
