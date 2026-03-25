local state = require("codetyper.state.state")
local open = require("codetyper.adapters.nvim.ui.logs_panel.open")

--- Ensure the logs panel is open (call before starting generation)
local function ensure_open()
  if not state.is_open then
    open()
  end
end

return ensure_open
