local state = require("codetyper.state.state")
local close_window = require("codetyper.adapters.nvim.ui.thinking.close_window")

--- Force close the thinking window and reset stage text
local function close()
  state.stage_text = "Thinking..."
  close_window()
end

return close
