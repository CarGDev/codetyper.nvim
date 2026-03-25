local utils = require("codetyper.support.utils")

--- Clear memories
---@param pattern string|nil Optional pattern to match
local function cmd_forget(pattern)
  local memory = require("codetyper.features.indexer.memory")

  if not pattern or pattern == "" then
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Clear all memories?",
    }, function(choice)
      if choice == "Yes" then
        memory.clear()
        utils.notify("All memories cleared", vim.log.levels.INFO)
      end
    end)
  else
    memory.clear(pattern)
    utils.notify("Cleared memories matching: " .. pattern, vim.log.levels.INFO)
  end
end

return cmd_forget
