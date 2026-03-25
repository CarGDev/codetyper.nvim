local utils = require("codetyper.support.utils")

--- Reset LLM accuracy statistics
local function cmd_llm_reset_stats()
  local selector = require("codetyper.core.llm.selector")
  selector.reset_accuracy_stats()
  utils.notify("LLM accuracy statistics reset", vim.log.levels.INFO)
end

return cmd_llm_reset_stats
