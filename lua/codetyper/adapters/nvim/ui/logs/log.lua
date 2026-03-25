local state = require("codetyper.state.state")
local get_timestamp = require("codetyper.utils.get_timestamp")

--- Add a log entry and notify all listeners
---@param level string Log level
---@param message string Log message
---@param data? table Optional data
local function log(level, message, data)
  local entry = {
    timestamp = get_timestamp(),
    level = level,
    message = message,
    data = data,
  }

  table.insert(state.entries, entry)

  for _, listener in ipairs(state.listeners) do
    pcall(listener, entry)
  end
end

return log
