local M = {}

--- Generate model breakdown section
---@param stats table Stats with by_model
---@param pricing_table table Pricing data
---@param normalize_model_fn fun(model: string): string
---@param is_free_fn fun(model: string): boolean
---@param formatters table { format_cost: fun(n): string, format_tokens: fun(n): string }
---@return string[] Lines
function M.generate_model_breakdown(stats, pricing_table, normalize_model_fn, is_free_fn, formatters)
  local lines = {}

  if next(stats.by_model) then
    -- Sort models by cost (descending)
    local models = {}
    for model, data in pairs(stats.by_model) do
      table.insert(models, { name = model, data = data })
    end
    table.sort(models, function(a, b)
      return a.data.cost > b.data.cost
    end)

    for _, item in ipairs(models) do
      local model = item.name
      local data = item.data
      local pricing = pricing_table[normalize_model_fn(model)]
      local is_free = data.is_free or is_free_fn(model)

      table.insert(lines, "")
      local model_icon = is_free and "🆓" or "💳"
      table.insert(lines, string.format("  %s %s", model_icon, model))
      table.insert(lines, string.format("     Requests: %d", data.requests))
      table.insert(lines, string.format("     Input:    %s tokens", formatters.format_tokens(data.input_tokens)))
      table.insert(lines, string.format("     Output:   %s tokens", formatters.format_tokens(data.output_tokens)))

      if is_free then
        if data.savings and data.savings > 0 then
          table.insert(lines, string.format("     Saved:    %s", formatters.format_cost(data.savings)))
        end
      else
        table.insert(lines, string.format("     Cost:     %s", formatters.format_cost(data.cost)))
      end

      -- Show pricing info for paid models
      if pricing and not is_free then
        local price_info =
          string.format("     Rate:     $%.2f/1M in, $%.2f/1M out", pricing.input or 0, pricing.output or 0)
        table.insert(lines, price_info)
      end
    end
  else
    table.insert(lines, "  No usage recorded.")
  end

  return lines
end

--- Generate full window content
---@param session_stats table Session statistics
---@param all_time_stats table All-time statistics
---@param deps table { comparison_model: string, pricing: table, normalize_model: function, is_free: function, formatters: table }
---@return string[] Lines for the buffer
function M.generate_content(session_stats, all_time_stats, deps)
  local format_cost = deps.formatters.format_cost
  local format_tokens = deps.formatters.format_tokens
  local format_duration = deps.formatters.format_duration
  local lines = {}

  -- Header
  table.insert(
    lines,
    "╔══════════════════════════════════════════════════════╗"
  )
  table.insert(lines, "║              💰 LLM Cost Estimation                  ║")
  table.insert(
    lines,
    "╠══════════════════════════════════════════════════════╣"
  )
  table.insert(lines, "")

  -- All-time summary (prominent)
  table.insert(lines, "🌐 All-Time Summary (Project)")
  table.insert(
    lines,
    "───────────────────────────────────────────────────────"
  )
  if all_time_stats.time_span > 0 then
    table.insert(lines, string.format("  Time span:      %s", format_duration(all_time_stats.time_span)))
  end
  table.insert(lines, string.format("  Requests:       %d total", all_time_stats.request_count))
  table.insert(lines, string.format("    Local/Free:   %d requests", all_time_stats.free_requests or 0))
  table.insert(lines, string.format("    Paid API:     %d requests", all_time_stats.paid_requests or 0))
  table.insert(lines, string.format("  Input tokens:   %s", format_tokens(all_time_stats.total_input)))
  table.insert(lines, string.format("  Output tokens:  %s", format_tokens(all_time_stats.total_output)))
  if all_time_stats.total_cached > 0 then
    table.insert(lines, string.format("  Cached tokens:  %s", format_tokens(all_time_stats.total_cached)))
  end
  table.insert(lines, "")
  table.insert(lines, string.format("  💵 Total Cost:  %s", format_cost(all_time_stats.total_cost)))

  -- Show savings prominently if there are any
  if all_time_stats.total_savings and all_time_stats.total_savings > 0 then
    table.insert(
      lines,
      string.format("  💚 Saved:       %s (vs %s)", format_cost(all_time_stats.total_savings), deps.comparison_model)
    )
  end
  table.insert(lines, "")

  -- Session summary
  table.insert(lines, "📊 Current Session")
  table.insert(
    lines,
    "───────────────────────────────────────────────────────"
  )
  table.insert(lines, string.format("  Duration:       %s", format_duration(session_stats.session_duration)))
  table.insert(
    lines,
    string.format(
      "  Requests:       %d (%d free, %d paid)",
      session_stats.request_count,
      session_stats.free_requests or 0,
      session_stats.paid_requests or 0
    )
  )
  table.insert(lines, string.format("  Input tokens:   %s", format_tokens(session_stats.total_input)))
  table.insert(lines, string.format("  Output tokens:  %s", format_tokens(session_stats.total_output)))
  if session_stats.total_cached > 0 then
    table.insert(lines, string.format("  Cached tokens:  %s", format_tokens(session_stats.total_cached)))
  end
  table.insert(lines, string.format("  Session Cost:   %s", format_cost(session_stats.total_cost)))
  if session_stats.total_savings and session_stats.total_savings > 0 then
    table.insert(lines, string.format("  Session Saved:  %s", format_cost(session_stats.total_savings)))
  end
  table.insert(lines, "")

  -- Per-model breakdown (all-time)
  table.insert(lines, "📈 Cost by Model (All-Time)")
  table.insert(
    lines,
    "───────────────────────────────────────────────────────"
  )
  local model_lines = M.generate_model_breakdown(all_time_stats, deps.pricing, deps.normalize_model, deps.is_free, deps.formatters)
  for _, line in ipairs(model_lines) do
    table.insert(lines, line)
  end

  table.insert(lines, "")
  table.insert(
    lines,
    "───────────────────────────────────────────────────────"
  )
  table.insert(lines, "  'q' close | 'r' refresh | 'c' clear session | 'C' all")
  table.insert(
    lines,
    "╚══════════════════════════════════════════════════════╝"
  )

  return lines
end

return M
