---@mod codetyper.cost Cost estimation for LLM usage
---@brief [[
--- Tracks token usage and estimates costs based on model pricing.
--- Prices are per 1M tokens. Persists usage data in the brain.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")

--- Cost history file name
local COST_HISTORY_FILE = "cost_history.json"

--- Get path to cost history file
---@return string File path
local function get_history_path()
  local root = utils.get_project_root()
  return root .. "/.codetyper/" .. COST_HISTORY_FILE
end

--- Default model for savings comparison (what you'd pay if not using Ollama)
M.comparison_model = "gpt-4o"

--- Models considered "free" (Ollama, local, Copilot subscription)
M.free_models = {
  ["ollama"] = true,
  ["codellama"] = true,
  ["llama2"] = true,
  ["llama3"] = true,
  ["mistral"] = true,
  ["deepseek-coder"] = true,
  ["copilot"] = true,
}

M.pricing = require("codetyper.constants.prices")

local state = require("codetyper.state.state")

--- Load historical usage from disk
function M.load_from_history()
  if state.loaded then
    return
  end

  local history_path = get_history_path()
  local content = utils.read_file(history_path)

  if content and content ~= "" then
    local ok, data = pcall(vim.json.decode, content)
    if ok and data and data.usage then
      state.all_usage = data.usage
    end
  end

  state.loaded = true
end

--- Save all usage to disk (debounced)
local save_timer = nil
local function save_to_disk()
  -- Cancel existing timer
  if save_timer then
    save_timer:stop()
    save_timer = nil
  end

  -- Debounce writes (500ms)
  save_timer = vim.loop.new_timer()
  save_timer:start(
    500,
    0,
    vim.schedule_wrap(function()
      local history_path = get_history_path()

      -- Ensure directory exists
      local dir = vim.fn.fnamemodify(history_path, ":h")
      utils.ensure_dir(dir)

      -- Merge session and historical usage
      local all_data = vim.deepcopy(state.all_usage)
      for _, usage in ipairs(state.usage) do
        table.insert(all_data, usage)
      end

      -- Save to file
      local data = {
        version = 1,
        updated = os.time(),
        usage = all_data,
      }

      local ok, json = pcall(vim.json.encode, data)
      if ok then
        utils.write_file(history_path, json)
      end

      save_timer = nil
    end)
  )
end

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
  if M.pricing[normalized] then
    return normalized
  end

  -- Try partial matches
  for price_model, _ in pairs(M.pricing) do
    if normalized:match(price_model) or price_model:match(normalized) then
      return price_model
    end
  end

  return normalized
end

--- Check if a model is considered "free" (local/Ollama/Copilot subscription)
---@param model string Model name
---@return boolean True if free
function M.is_free_model(model)
  local normalized = normalize_model(model)

  -- Check direct match
  if M.free_models[normalized] then
    return true
  end

  -- Check if it's an Ollama model (any model with : in name like deepseek-coder:6.7b)
  if model:match(":") then
    return true
  end

  -- Check pricing - if cost is 0, it's free
  local pricing = M.pricing[normalized]
  if pricing and pricing.input == 0 and pricing.output == 0 then
    return true
  end

  return false
end

--- Calculate cost for token usage
---@param model string Model name
---@param input_tokens number Input tokens
---@param output_tokens number Output tokens
---@param cached_tokens? number Cached input tokens
---@return number Cost in USD
function M.calculate_cost(model, input_tokens, output_tokens, cached_tokens)
  local normalized = normalize_model(model)
  local pricing = M.pricing[normalized]

  if not pricing then
    -- Unknown model, return 0
    return 0
  end

  cached_tokens = cached_tokens or 0
  local regular_input = input_tokens - cached_tokens

  -- Calculate cost (prices are per 1M tokens)
  local input_cost = (regular_input / 1000000) * (pricing.input or 0)
  local cached_cost = (cached_tokens / 1000000) * (pricing.cached_input or pricing.input or 0)
  local output_cost = (output_tokens / 1000000) * (pricing.output or 0)

  return input_cost + cached_cost + output_cost
end

--- Calculate estimated savings (what would have been paid if using comparison model)
---@param input_tokens number Input tokens
---@param output_tokens number Output tokens
---@param cached_tokens? number Cached input tokens
---@return number Estimated savings in USD
function M.calculate_savings(input_tokens, output_tokens, cached_tokens)
  -- Calculate what it would have cost with the comparison model
  return M.calculate_cost(M.comparison_model, input_tokens, output_tokens, cached_tokens)
end

--- Record token usage
---@param model string Model name
---@param input_tokens number Input tokens
---@param output_tokens number Output tokens
---@param cached_tokens? number Cached input tokens
function M.record_usage(model, input_tokens, output_tokens, cached_tokens)
  cached_tokens = cached_tokens or 0
  local cost = M.calculate_cost(model, input_tokens, output_tokens, cached_tokens)

  -- Calculate savings if using a free model
  local savings = 0
  if M.is_free_model(model) then
    savings = M.calculate_savings(input_tokens, output_tokens, cached_tokens)
  end

  table.insert(state.usage, {
    model = model,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cached_tokens = cached_tokens,
    timestamp = os.time(),
    cost = cost,
    savings = savings,
    is_free = M.is_free_model(model),
  })

  -- Save to disk (debounced)
  save_to_disk()

  -- Update window if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.refresh_window()
  end
end

--- Aggregate usage data into stats
---@param usage_list CostUsage[] List of usage records
---@return table Stats
local function aggregate_usage(usage_list)
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
      if M.is_free_model(model) then
        usage_savings = M.calculate_savings(usage.input_tokens or 0, usage.output_tokens or 0, usage.cached_tokens or 0)
      end
    end
    stats.total_savings = stats.total_savings + usage_savings

    -- Track free vs paid
    local is_free = usage.is_free
    if is_free == nil then
      is_free = M.is_free_model(usage.model or "unknown")
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

--- Get session statistics
---@return table Statistics
function M.get_stats()
  local stats = aggregate_usage(state.usage)
  stats.session_duration = os.time() - state.session_start
  return stats
end

--- Get all-time statistics (session + historical)
---@return table Statistics
function M.get_all_time_stats()
  -- Load history if not loaded
  M.load_from_history()

  -- Combine session and historical usage
  local all_usage = vim.deepcopy(state.all_usage)
  for _, usage in ipairs(state.usage) do
    table.insert(all_usage, usage)
  end

  local stats = aggregate_usage(all_usage)

  -- Calculate time span
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

--- Format cost as string
---@param cost number Cost in USD
---@return string Formatted cost
local function format_cost(cost)
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
local function format_tokens(tokens)
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
local function format_duration(seconds)
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

--- Generate model breakdown section
---@param stats table Stats with by_model
---@return string[] Lines
local function generate_model_breakdown(stats)
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
      local pricing = M.pricing[normalize_model(model)]
      local is_free = data.is_free or M.is_free_model(model)

      table.insert(lines, "")
      local model_icon = is_free and "🆓" or "💳"
      table.insert(lines, string.format("  %s %s", model_icon, model))
      table.insert(lines, string.format("     Requests: %d", data.requests))
      table.insert(lines, string.format("     Input:    %s tokens", format_tokens(data.input_tokens)))
      table.insert(lines, string.format("     Output:   %s tokens", format_tokens(data.output_tokens)))

      if is_free then
        -- Show savings for free models
        if data.savings and data.savings > 0 then
          table.insert(lines, string.format("     Saved:    %s", format_cost(data.savings)))
        end
      else
        table.insert(lines, string.format("     Cost:     %s", format_cost(data.cost)))
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

--- Generate window content
---@return string[] Lines for the buffer
local function generate_content()
  local session_stats = M.get_stats()
  local all_time_stats = M.get_all_time_stats()
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
      string.format("  💚 Saved:       %s (vs %s)", format_cost(all_time_stats.total_savings), M.comparison_model)
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
  local model_lines = generate_model_breakdown(all_time_stats)
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

--- Refresh the cost window content
function M.refresh_window()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = generate_content()

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

--- Open the cost estimation window
function M.open()
  -- Load historical data if not loaded
  M.load_from_history()

  -- Close existing window if open
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "codetyper-cost"

  -- Calculate window size
  local width = 58
  local height = 40
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Cost Estimation ",
    title_pos = "center",
  })

  -- Set window options
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = false

  -- Populate content
  M.refresh_window()

  -- Set up keymaps
  local opts = { buffer = state.buf, silent = true }
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "r", function()
    M.refresh_window()
  end, opts)
  vim.keymap.set("n", "c", function()
    M.clear_session()
    M.refresh_window()
  end, opts)
  vim.keymap.set("n", "C", function()
    M.clear_all()
    M.refresh_window()
  end, opts)

  -- Set up highlights
  vim.api.nvim_buf_call(state.buf, function()
    vim.fn.matchadd("Title", "LLM Cost Estimation")
    vim.fn.matchadd("Number", "\\$[0-9.]*")
    vim.fn.matchadd("Keyword", "[0-9.]*[KM]\\? tokens")
    vim.fn.matchadd("Special", "🤖\\|💰\\|📊\\|📈\\|💵")
  end)
end

--- Close the cost window
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

--- Toggle the cost window
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

--- Clear session usage (not history)
function M.clear_session()
  state.usage = {}
  state.session_start = os.time()
  utils.notify("Session cost tracking cleared", vim.log.levels.INFO)
end

--- Clear all history (session + saved)
function M.clear_all()
  state.usage = {}
  state.all_usage = {}
  state.session_start = os.time()
  state.loaded = false

  -- Delete history file
  local history_path = get_history_path()
  local ok, err = os.remove(history_path)
  if not ok and err and not err:match("No such file") then
    utils.notify("Failed to delete history: " .. err, vim.log.levels.WARN)
  end

  utils.notify("All cost history cleared", vim.log.levels.INFO)
end

--- Clear usage history (alias for clear_session)
function M.clear()
  M.clear_session()
end

--- Reset session
function M.reset()
  M.clear_session()
end

return M
