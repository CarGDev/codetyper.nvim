local state = require("codetyper.state.state")
local open = require("codetyper.adapters.nvim.ui.logs_panel.open")
local close = require("codetyper.adapters.nvim.ui.logs_panel.close")

--- Toggle the logs panel open/closed
local function toggle()
  if state.is_open then
    close()
  else
    open()
  end
end

return toggle
