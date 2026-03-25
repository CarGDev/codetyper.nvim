local state = require("codetyper.state.state")

--- Check if the thinking window is currently visible
---@return boolean
local function is_shown()
  return state.win_id ~= nil and vim.api.nvim_win_is_valid(state.win_id)
end

return is_shown
