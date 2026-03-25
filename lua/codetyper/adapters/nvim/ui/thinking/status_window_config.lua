local get_ui_dimensions = require("codetyper.utils.get_config")

--- Build the floating window config for the top-right status indicator
---@return table
local function status_window_config()
  local width, _ = get_ui_dimensions()
  local win_width = math.min(40, math.floor(width / 3))
  return {
    relative = "editor",
    row = 0,
    col = width,
    width = win_width,
    height = 2,
    anchor = "NE",
    style = "minimal",
    border = nil,
    zindex = 100,
  }
end

return status_window_config
