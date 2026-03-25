local state = require("codetyper.state.state")

--- Clear all logs and reset counters
local function clear()
  state.entries = {}
  state.total_prompt_tokens = 0
  state.total_response_tokens = 0
  state.current_provider = nil
  state.current_model = nil

  for _, listener in ipairs(state.listeners) do
    pcall(listener, { level = "clear" })
  end
end

return clear
