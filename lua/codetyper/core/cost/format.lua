local M = {}

--- Format cost as string
---@param cost number Cost in USD
---@return string Formatted cost
function M.format_cost(cost)
  if cost < 0.01 then
    return string.format("$%.4f", cost)
  elseif cost < 1 then
    return string.format("$%.3f", cost)
  else
    return string.format("$%.2f", cost)
  end
end

--- Format token count
---@param tokens number Token count
---@return string Formatted count
function M.format_tokens(tokens)
  if tokens >= 1000000 then
    return string.format("%.2fM", tokens / 1000000)
  elseif tokens >= 1000 then
    return string.format("%.1fK", tokens / 1000)
  else
    return tostring(tokens)
  end
end

--- Format duration
---@param seconds number Duration in seconds
---@return string Formatted duration
function M.format_duration(seconds)
  if seconds < 60 then
    return string.format("%ds", seconds)
  elseif seconds < 3600 then
    return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
  else
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, mins)
  end
end

return M
