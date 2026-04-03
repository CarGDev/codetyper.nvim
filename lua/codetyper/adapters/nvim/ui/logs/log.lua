local state = require("codetyper.state.state")
local get_timestamp = require("codetyper.utils.get_timestamp")

local MAX_ENTRIES = 10000

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

  -- Cap entries to prevent unbounded memory growth
  if #state.entries > MAX_ENTRIES then
    -- Remove oldest 20% to avoid frequent trimming
    local trim_count = math.floor(MAX_ENTRIES * 0.2)
    for _ = 1, trim_count do
      table.remove(state.entries, 1)
    end
  end

  for _, listener in ipairs(state.listeners) do
    pcall(listener, entry)
  end
end

return log
