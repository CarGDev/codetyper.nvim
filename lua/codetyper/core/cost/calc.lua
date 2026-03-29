local M = {}

--- Calculate cost for token usage
---@param model string Model name
---@param input_tokens number Input tokens
---@param output_tokens number Output tokens
---@param cached_tokens number|nil Cached input tokens
---@param normalize_model_fn fun(model: string): string
---@param pricing_table table<string, {input: number, cached_input: number|nil, output: number}>
---@return number Cost in USD
function M.calculate_cost(model, input_tokens, output_tokens, cached_tokens, normalize_model_fn, pricing_table)
  local normalized = normalize_model_fn(model)
  local pricing = pricing_table[normalized]

  if not pricing then
    return 0
  end

  cached_tokens = cached_tokens or 0
  local regular_input = input_tokens - cached_tokens

  local input_cost = (regular_input / 1000000) * (pricing.input or 0)
  local cached_cost = (cached_tokens / 1000000) * (pricing.cached_input or pricing.input or 0)
  local output_cost = (output_tokens / 1000000) * (pricing.output or 0)

  return input_cost + cached_cost + output_cost
end

--- Calculate estimated savings (what would have been paid if using comparison model)
---@param input_tokens number Input tokens
---@param output_tokens number Output tokens
---@param cached_tokens number|nil Cached input tokens
---@param comparison_model string Model to compare against
---@param normalize_model_fn fun(model: string): string
---@param pricing_table table
---@return number Estimated savings in USD
function M.calculate_savings(input_tokens, output_tokens, cached_tokens, comparison_model, normalize_model_fn, pricing_table)
  return M.calculate_cost(comparison_model, input_tokens, output_tokens, cached_tokens, normalize_model_fn, pricing_table)
end

return M
