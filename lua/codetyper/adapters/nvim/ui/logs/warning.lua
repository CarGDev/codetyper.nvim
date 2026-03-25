local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log warning message
---@param message string
---@param data? table
local function warning(message, data)
  log("warning", "WARN: " .. message, data)
end

return warning
