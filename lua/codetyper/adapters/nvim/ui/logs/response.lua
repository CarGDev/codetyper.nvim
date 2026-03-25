local state = require("codetyper.state.state")
local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log API response with token usage
---@param prompt_tokens number Tokens used in prompt
---@param response_tokens number Tokens in response
---@param stop_reason? string Why the response stopped
local function response(prompt_tokens, response_tokens, stop_reason)
  state.total_prompt_tokens = state.total_prompt_tokens + prompt_tokens
  state.total_response_tokens = state.total_response_tokens + response_tokens

  local message = string.format(
    "Tokens: %d in / %d out | Total: %d in / %d out",
    prompt_tokens,
    response_tokens,
    state.total_prompt_tokens,
    state.total_response_tokens
  )

  if stop_reason then
    message = message .. " | Stop: " .. stop_reason
  end

  log("response", message, {
    prompt_tokens = prompt_tokens,
    response_tokens = response_tokens,
    total_prompt = state.total_prompt_tokens,
    total_response = state.total_response_tokens,
    stop_reason = stop_reason,
  })
end

return response
