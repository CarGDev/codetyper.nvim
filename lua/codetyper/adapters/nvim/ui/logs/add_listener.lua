local state = require("codetyper.state.state")

--- Register a listener for new log entries
---@param callback fun(entry: LogEntry)
---@return number listener_id Listener ID for removal
local function add_listener(callback)
  table.insert(state.listeners, callback)
  return #state.listeners
end

return add_listener
