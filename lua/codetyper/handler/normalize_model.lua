local pricing = require("codetyper.constants.prices")

--- Normalize model name for pricing lookup
---@param model string Model name from API
---@return string Normalized model name
local function normalize_model(model)
  if not model then
    return "unknown"
  end

  -- Convert to lowercase
  local normalized = model:lower()

  -- Handle Copilot models
  if normalized:match("copilot") then
    return "copilot"
  end

  -- Handle common prefixes
  normalized = normalized:gsub("^copilot/", "")

  -- Try exact match first
  if pricing[normalized] then
    return normalized
  end

  -- Try partial matches
  for price_model, _ in pairs(pricing) do
    if normalized:match(price_model) or price_model:match(normalized) then
      return price_model
    end
  end

  return normalized
end

return normalize_model
