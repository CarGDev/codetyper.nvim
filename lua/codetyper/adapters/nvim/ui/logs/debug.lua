local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log debug message
---@param message string
---@param data? table
local function debug(message, data)
  log("debug", message, data)
end

return debug
