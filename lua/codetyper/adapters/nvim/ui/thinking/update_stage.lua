local state = require("codetyper.state.state")

--- Update the displayed stage text (e.g. "Reading context...", "Sending to LLM...")
---@param text string
local function update_stage(text)
  state.stage_text = text
end

return update_stage
