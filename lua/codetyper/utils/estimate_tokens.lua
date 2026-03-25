--- Estimate token count for a string (rough approximation ~4 chars per token)
---@param text string
---@return number
local function estimate_tokens(text)
  return math.ceil(#text / 4)
end

return estimate_tokens
