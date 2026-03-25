local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log explore done with stats
---@param tool_uses number Number of tool uses
---@param tokens number Tokens used
---@param duration number Duration in seconds
local function explore_done(tool_uses, tokens, duration)
  log(
    "result",
    string.format("  ⎿  Done (%d tool uses · %.1fk tokens · %.1fs)", tool_uses, tokens / 1000, duration)
  )
end

return explore_done
