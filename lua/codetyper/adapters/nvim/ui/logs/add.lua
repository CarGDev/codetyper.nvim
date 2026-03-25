local log = require("codetyper.adapters.nvim.ui.logs.log")
local clear = require("codetyper.adapters.nvim.ui.logs.clear")

--- Add log entry (compatibility function for scheduler)
--- Accepts {type = "info", message = "..."} format
---@param entry table Log entry with type and message
local function add(entry)
  if entry.type == "clear" then
    clear()
    return
  end
  log(entry.type or "info", entry.message or "", entry.data)
end

return add
