local active_count = require("codetyper.adapters.nvim.ui.thinking.active_count")
local close_window = require("codetyper.adapters.nvim.ui.thinking.close_window")

--- Hide the thinking window if no active queue items remain
local function check_and_hide()
  if active_count() > 0 then
    return
  end
  close_window()
end

return check_and_hide
