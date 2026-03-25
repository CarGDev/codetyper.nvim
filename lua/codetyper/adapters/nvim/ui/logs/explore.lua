local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log explore/search operation
---@param description string What we're exploring
local function explore(description)
  log("action", string.format("Explore(%s)", description))
end

return explore
