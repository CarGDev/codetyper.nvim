---@class HookContext
---@field tool_name string
---@field input table
---@field result? any
---@field error? string
---@field start_time? number
---@field end_time? number
---@field duration_ms? number

---@alias HookCallback fun(ctx: HookContext): boolean|nil

local M = {}

---@type table<string, HookCallback[]>
local hooks = {
  pre_tool = {},
  post_tool = {},
  tool_error = {},
  tool_timeout = {},
}

---Register a hook callback
---@param hook_type string "pre_tool" | "post_tool" | "tool_error" | "tool_timeout"
---@param callback HookCallback
---@return function unregister Function to unregister this hook
function M.register(hook_type, callback)
  if not hooks[hook_type] then
    error(string.format("Unknown hook type: %s", hook_type))
  end

  table.insert(hooks[hook_type], callback)

  -- Return unregister function
  return function()
    for i, cb in ipairs(hooks[hook_type]) do
      if cb == callback then
        table.remove(hooks[hook_type], i)
        return
      end
    end
  end
end

---Invoke all hooks of a given type
---@param hook_type string
---@param context HookContext
---@return boolean success True if all hooks passed, false if any hook rejected
function M.invoke(hook_type, context)
  local hook_list = hooks[hook_type]
  if not hook_list or #hook_list == 0 then
    return true
  end

  for i, callback in ipairs(hook_list) do
    local ok, result = pcall(callback, context)

    if not ok then
      -- Hook crashed, log error but continue
      local err_msg = string.format("Hook #%d crashed in %s: %s", i, hook_type, tostring(result))
      vim.schedule(function()
        vim.notify(err_msg, vim.log.levels.ERROR)
      end)
    elseif result == false then
      -- Hook explicitly rejected
      return false
    end
  end

  return true
end

---Clear all hooks of a given type
---@param hook_type? string If nil, clears all hooks
function M.clear(hook_type)
  if hook_type then
    hooks[hook_type] = {}
  else
    for key in pairs(hooks) do
      hooks[key] = {}
    end
  end
end

---Get count of registered hooks
---@param hook_type? string If nil, returns total count across all types
---@return number
function M.count(hook_type)
  if hook_type then
    return #(hooks[hook_type] or {})
  else
    local total = 0
    for _, hook_list in pairs(hooks) do
      total = total + #hook_list
    end
    return total
  end
end

---Create a timing wrapper for tool execution
---@param context HookContext
---@return HookContext enhanced_context Context with timing information
function M.start_timing(context)
  context.start_time = vim.loop.hrtime()
  return context
end

---Complete timing for a tool execution
---@param context HookContext
---@return HookContext enhanced_context Context with duration calculated
function M.end_timing(context)
  if context.start_time then
    context.end_time = vim.loop.hrtime()
    context.duration_ms = (context.end_time - context.start_time) / 1000000
  end
  return context
end

-- Built-in hooks for logging (optional, can be disabled)
local logging_enabled = true

---Enable or disable built-in logging hooks
---@param enabled boolean
function M.set_logging(enabled)
  logging_enabled = enabled
end

-- Register built-in logging hooks
M.register("pre_tool", function(ctx)
  if not logging_enabled then
    return true
  end

  local input_preview = vim.inspect(ctx.input)
  if #input_preview > 100 then
    input_preview = input_preview:sub(1, 100) .. "..."
  end

  vim.schedule(function()
    vim.notify(
      string.format("[Agent] Executing: %s", ctx.tool_name),
      vim.log.levels.DEBUG
    )
  end)

  return true
end)

M.register("post_tool", function(ctx)
  if not logging_enabled then
    return true
  end

  local duration_str = ctx.duration_ms and string.format(" (%.2fms)", ctx.duration_ms) or ""

  if ctx.error then
    vim.schedule(function()
      vim.notify(
        string.format("[Agent] Failed: %s%s - %s", ctx.tool_name, duration_str, ctx.error),
        vim.log.levels.ERROR
      )
    end)
  else
    vim.schedule(function()
      vim.notify(
        string.format("[Agent] Completed: %s%s", ctx.tool_name, duration_str),
        vim.log.levels.DEBUG
      )
    end)
  end

  return true
end)

M.register("tool_error", function(ctx)
  if not logging_enabled then
    return true
  end

  vim.schedule(function()
    vim.notify(
      string.format("[Agent] Error in %s: %s", ctx.tool_name, ctx.error),
      vim.log.levels.ERROR
    )
  end)

  return true
end)

M.register("tool_timeout", function(ctx)
  if not logging_enabled then
    return true
  end

  vim.schedule(function()
    vim.notify(
      string.format("[Agent] Timeout in %s", ctx.tool_name),
      vim.log.levels.WARN
    )
  end)

  return true
end)

return M
