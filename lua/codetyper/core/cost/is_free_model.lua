local pricing = require("codetyper.constants.prices")
local normalize_model = require("codetyper.handler.normalize_model")
local free_models = require("codetyper.constants.models").free_models

--- Check if a model is considered "free" (local/Ollama/Copilot subscription)
---@param model string Model name
---@return boolean True if free
local function is_free_model(model)
  local normalized = normalize_model(model)

  -- Check direct match
  if free_models[normalized] then
    return true
  end

  -- Check if it's an Ollama model (any model with : in name like deepseek-coder:6.7b)
  if model:match(":") then
    return true
  end

  -- Check pricing - if cost is 0, it's free
  local normalizedPricing = pricing[normalized]
  if normalizedPricing and normalizedPricing.input == 0 and normalizedPricing.output == 0 then
    return true
  end

  return false
end

return is_free_model
