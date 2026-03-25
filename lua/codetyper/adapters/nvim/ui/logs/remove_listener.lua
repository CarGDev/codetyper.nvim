local state = require("codetyper.state.state")

--- Remove a listener by ID
---@param listener_id number Listener ID
local function remove_listener(listener_id)
  if listener_id > 0 and listener_id <= #state.listeners then
    table.remove(state.listeners, listener_id)
  end
end

return remove_listener
