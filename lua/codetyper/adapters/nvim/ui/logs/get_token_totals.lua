local state = require("codetyper.state.state")

--- Get token totals
---@return number prompt_tokens
---@return number response_tokens
local function get_token_totals()
  return state.total_prompt_tokens, state.total_response_tokens
end

return get_token_totals
