local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log thinking/reasoning step
---@param step string Description of what's happening
local function thinking(step)
  log("thinking", step)
end

return thinking
