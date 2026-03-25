--- Reset processed prompts to allow re-processing
local function cmd_reset()
  local reset_processed = require("codetyper.adapters.nvim.autocmds.reset_processed")
  reset_processed()
end

return cmd_reset
