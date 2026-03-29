local M = {}

local state = require("codetyper.state.state")
local aggregate_mod = require("codetyper.core.cost.aggregate")
local calc = require("codetyper.core.cost.calc")
local is_free_model = require("codetyper.core.cost.is_free_model")
local normalize_model = require("codetyper.handler.normalize_model")
local pricing = require("codetyper.constants.prices")
local comparison_model = require("codetyper.constants.models").comparison_model
local load_from_history = require("codetyper.utils.load_from_history")

local function calculate_savings(input_tokens, output_tokens, cached_tokens)
  return calc.calculate_savings(input_tokens, output_tokens, cached_tokens, comparison_model, normalize_model, pricing)
end

--- Get session statistics
---@return table Statistics
function M.get_stats()
  local stats = aggregate_mod.aggregate_usage(state.usage, is_free_model, calculate_savings)
  stats.session_duration = os.time() - state.session_start
  return stats
end

--- Get all-time statistics (session + historical)
---@return table Statistics
function M.get_all_time_stats()
  load_from_history()

  local all_usage = vim.deepcopy(state.all_usage)
  for _, usage in ipairs(state.usage) do
    table.insert(all_usage, usage)
  end

  local stats = aggregate_mod.aggregate_usage(all_usage, is_free_model, calculate_savings)

  if #all_usage > 0 then
    local oldest = all_usage[1].timestamp or os.time()
    for _, usage in ipairs(all_usage) do
      if usage.timestamp and usage.timestamp < oldest then
        oldest = usage.timestamp
      end
    end
    stats.time_span = os.time() - oldest
  else
    stats.time_span = 0
  end

  return stats
end

return M
