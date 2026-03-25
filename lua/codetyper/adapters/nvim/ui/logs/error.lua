local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log error message
---@param message string
---@param data? table
local function log_error(message, data)
  log("error", "ERROR: " .. message, data)
end

return log_error
