local state = require("codetyper.state.state")
local calc = require("codetyper.core.cost.calc")
local is_free_model = require("codetyper.core.cost.is_free_model")
local normalize_model = require("codetyper.handler.normalize_model")
local pricing = require("codetyper.constants.prices")
local comparison_model = require("codetyper.constants.models").comparison_model
local save_to_disk = require("codetyper.handler.save_timer")

--- Record token usage
---@param model string Model name
---@param input_tokens number Input tokens
---@param output_tokens number Output tokens
---@param cached_tokens? number Cached input tokens
local function record_usage(model, input_tokens, output_tokens, cached_tokens)
  cached_tokens = cached_tokens or 0
  local cost = calc.calculate_cost(model, input_tokens, output_tokens, cached_tokens, normalize_model, pricing)

  local savings = 0
  if is_free_model(model) then
    savings = calc.calculate_savings(input_tokens, output_tokens, cached_tokens, comparison_model, normalize_model, pricing)
  end

  table.insert(state.usage, {
    model = model,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cached_tokens = cached_tokens,
    timestamp = os.time(),
    cost = cost,
    savings = savings,
    is_free = is_free_model(model),
  })

  save_to_disk()

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local window = require("codetyper.window.cost")
    window.refresh_window()
  end
end

return record_usage
