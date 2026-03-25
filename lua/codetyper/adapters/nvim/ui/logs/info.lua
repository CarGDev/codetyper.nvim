local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log info message
---@param message string
---@param data? table
local function info(message, data)
  log("info", message, data)
end

return info
