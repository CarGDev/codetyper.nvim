local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log a reasoning/explanation message (shown prominently)
---@param message string The reasoning message
local function reason(message)
  log("reason", message)
end

return reason
