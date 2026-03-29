local M = {}

--- Aggregate usage data into stats
---@param usage_list table[] List of usage records
---@param is_free_fn fun(model: string): boolean
---@param calculate_savings_fn fun(input_tokens: number, output_tokens: number, cached_tokens: number|nil): number
---@return table Stats
function M.aggregate_usage(usage_list, is_free_fn, calculate_savings_fn)
  local stats = {
    total_input = 0,
    total_output = 0,
    total_cached = 0,
    total_cost = 0,
    total_savings = 0,
    free_requests = 0,
    paid_requests = 0,
    by_model = {},
    request_count = #usage_list,
  }

  for _, usage in ipairs(usage_list) do
    stats.total_input = stats.total_input + (usage.input_tokens or 0)
    stats.total_output = stats.total_output + (usage.output_tokens or 0)
    stats.total_cached = stats.total_cached + (usage.cached_tokens or 0)
    stats.total_cost = stats.total_cost + (usage.cost or 0)

    -- Track savings
    local usage_savings = usage.savings or 0
    -- For historical data without savings field, calculate it
    if usage_savings == 0 and usage.is_free == nil then
      local model = usage.model or "unknown"
      if is_free_fn(model) then
        usage_savings = calculate_savings_fn(usage.input_tokens or 0, usage.output_tokens or 0, usage.cached_tokens or 0)
      end
    end
    stats.total_savings = stats.total_savings + usage_savings

    -- Track free vs paid
    local is_free = usage.is_free
    if is_free == nil then
      is_free = is_free_fn(usage.model or "unknown")
    end
    if is_free then
      stats.free_requests = stats.free_requests + 1
    else
      stats.paid_requests = stats.paid_requests + 1
    end

    local model = usage.model or "unknown"
    if not stats.by_model[model] then
      stats.by_model[model] = {
        input_tokens = 0,
        output_tokens = 0,
        cached_tokens = 0,
        cost = 0,
        savings = 0,
        requests = 0,
        is_free = is_free,
      }
    end

    stats.by_model[model].input_tokens = stats.by_model[model].input_tokens + (usage.input_tokens or 0)
    stats.by_model[model].output_tokens = stats.by_model[model].output_tokens + (usage.output_tokens or 0)
    stats.by_model[model].cached_tokens = stats.by_model[model].cached_tokens + (usage.cached_tokens or 0)
    stats.by_model[model].cost = stats.by_model[model].cost + (usage.cost or 0)
    stats.by_model[model].savings = stats.by_model[model].savings + usage_savings
    stats.by_model[model].requests = stats.by_model[model].requests + 1
  end

  return stats
end

return M
