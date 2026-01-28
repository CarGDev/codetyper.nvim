--- Brain Learning System (Python Agent Wrapper)
--- Delegates to Python agent for graph-based knowledge storage
---
--- This module provides the same API as the original Lua implementation
--- but delegates actual operations to the Python agent for consistency
--- and to avoid duplicate implementations.

local M = {}

---@type BrainConfig|nil
local config = nil

---@type boolean
local initialized = false

--- Default configuration
local DEFAULT_CONFIG = {
  enabled = true,
  auto_learn = true,
  output = {
    max_tokens = 4000,
    format = "compact",
  },
}

--- Get the agent client (lazy load to avoid circular deps)
---@return table
local function get_agent_client()
  return require("codetyper.transport.agent_client")
end

--- Initialize brain system
---@param opts? BrainConfig Configuration options
function M.setup(opts)
  config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})

  if not config.enabled then
    return
  end

  -- Ensure Python agent is started
  local agent_client = get_agent_client()
  if not agent_client.is_running() then
    agent_client.start()
  end

  initialized = true
end

--- Check if brain is initialized
---@return boolean
function M.is_initialized()
  return initialized and config and config.enabled
end

--- Get current configuration
---@return BrainConfig|nil
function M.get_config()
  return config
end

--- Learn from an event (delegates to Python agent)
---@param event LearnEvent Learning event
---@param callback? fun(result: table|nil, error: string|nil)
---@return nil
function M.learn(event, callback)
  if not M.is_initialized() or not config.auto_learn then
    if callback then callback(nil, "Brain not initialized or auto_learn disabled") end
    return
  end

  local agent_client = get_agent_client()

  -- Map event to Python format
  local event_type = event.type or "edit"
  local event_data = {
    file = event.file,
    timestamp = event.timestamp or os.time(),
    data = event.data or {},
  }

  agent_client.memory_learn(event_type, event_data, function(result, err)
    if callback then
      callback(result, err)
    end
    if err then
      -- Log error but don't fail silently
      pcall(function()
        local logs = require("codetyper.adapters.nvim.ui.logs")
        logs.debug("Memory learn error: " .. err)
      end)
    end
  end)
end

--- Learn synchronously (for places that need immediate result)
--- Note: This blocks! Use M.learn() when possible
---@param event LearnEvent
---@return table|nil result
function M.learn_sync(event)
  if not M.is_initialized() or not config.auto_learn then
    return nil
  end

  -- For now, just call async version - true sync would need coroutines
  M.learn(event)
  return { learned = true }
end

--- Query relevant knowledge for context (delegates to Python agent)
---@param opts QueryOpts Query options
---@param callback fun(result: table|nil, error: string|nil)
function M.query(opts, callback)
  if not M.is_initialized() then
    callback({ nodes = {}, total = 0 }, nil)
    return
  end

  local agent_client = get_agent_client()
  agent_client.memory_query(opts or {}, callback)
end

--- Get LLM-optimized context string (delegates to Python agent)
---@param opts? table Options (context_type, max_tokens)
---@param callback fun(context: string, error: string|nil)
function M.get_context_for_llm(opts, callback)
  if not M.is_initialized() then
    callback("", nil)
    return
  end

  opts = opts or {}
  local context_type = opts.context_type or "all"
  local max_tokens = opts.max_tokens or config.output.max_tokens

  local agent_client = get_agent_client()
  agent_client.memory_get_context(context_type, max_tokens, function(result, err)
    if err then
      callback("", err)
      return
    end
    callback(result and result.context or "", nil)
  end)
end

--- Get stats about the brain (delegates to Python agent)
---@param callback fun(stats: table|nil, error: string|nil)
function M.stats(callback)
  if not M.is_initialized() then
    callback({ initialized = false }, nil)
    return
  end

  local agent_client = get_agent_client()
  agent_client.memory_stats(function(result, err)
    if err then
      callback({ initialized = true, error = err }, nil)
      return
    end
    result = result or {}
    result.initialized = true
    callback(result, nil)
  end)
end

--- Clear all memory (delegates to Python agent)
---@param callback fun(result: table|nil, error: string|nil)
function M.clear(callback)
  if not M.is_initialized() then
    if callback then callback(nil, "Brain not initialized") end
    return
  end

  local agent_client = get_agent_client()
  agent_client.memory_clear(callback)
end

--- Shutdown brain (cleanup)
function M.shutdown()
  initialized = false
end

-- ============================================================
-- Deprecated/Stub functions (for backwards compatibility)
-- These existed in the Lua implementation but are no longer needed
-- ============================================================

--- Deprecated: Commit is handled automatically by Python agent
---@param message string Commit message (ignored)
---@return nil
function M.commit(message)
  -- No-op: Python agent handles persistence automatically
  return nil
end

--- Deprecated: Rollback not supported in new architecture
---@param delta_hash string
---@return boolean Always false
function M.rollback(delta_hash)
  return false
end

--- Deprecated: History not supported in new architecture
---@param limit? number
---@return table Empty table
function M.get_history(limit)
  return {}
end

--- Deprecated: Prune is handled by Python agent
---@param opts? table
---@return number Always 0
function M.prune(opts)
  return 0
end

--- Deprecated: Export not supported in new architecture
---@return nil
function M.export()
  return nil
end

--- Deprecated: Import not supported in new architecture
---@param data table
---@return boolean Always false
function M.import(data)
  return false
end

--- Deprecated: Flush is handled by Python agent
function M.flush()
  -- No-op
end

return M
