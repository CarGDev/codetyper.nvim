local utils = require("codetyper.support.utils")

--- Report feedback on last LLM response
---@param was_good boolean Whether the response was good
local function cmd_llm_feedback(was_good)
  local llm = require("codetyper.core.llm")
  local provider = "ollama"

  llm.report_feedback(provider, was_good)
  local feedback_type = was_good and "positive" or "negative"
  utils.notify(string.format("Reported %s feedback for %s", feedback_type, provider), vim.log.levels.INFO)
end

return cmd_llm_feedback
