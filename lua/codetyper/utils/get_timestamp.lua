--- Get current timestamp formatted as HH:MM:SS
---@return string
local function get_timestamp()
  return os.date("%H:%M:%S")
end

return get_timestamp
