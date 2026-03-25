local state = require("codetyper.state.state")

--- Get current provider info
---@return string|nil provider
---@return string|nil model
local function get_provider_info()
  return state.current_provider, state.current_model
end

return get_provider_info
