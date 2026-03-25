local state = require("codetyper.state.state")
local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log API request
---@param provider string LLM provider
---@param model string Model name
---@param prompt_tokens? number Estimated prompt tokens
local function request(provider, model, prompt_tokens)
  state.current_provider = provider
  state.current_model = model

  local message = string.format("[%s] %s", provider:upper(), model)
  if prompt_tokens then
    message = message .. string.format(" | Prompt: ~%d tokens", prompt_tokens)
  end

  log("request", message, {
    provider = provider,
    model = model,
    prompt_tokens = prompt_tokens,
  })
end

return request
