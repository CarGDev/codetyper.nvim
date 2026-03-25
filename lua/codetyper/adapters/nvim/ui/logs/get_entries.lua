local state = require("codetyper.state.state")

--- Get all log entries
---@return LogEntry[]
local function get_entries()
  return state.entries
end

return get_entries
