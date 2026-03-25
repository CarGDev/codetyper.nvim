local state = require("codetyper.state.state")

--- Check if the diff review UI is open
---@return boolean
local function is_open()
  return state.is_open
end

return is_open
