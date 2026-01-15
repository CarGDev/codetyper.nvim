--- Brain Learning System
--- Graph-based knowledge storage with delta versioning

local storage = require("codetyper.brain.storage")
local types = require("codetyper.brain.types")

local M = {}

---@type BrainConfig|nil
local config = nil

---@type boolean
local initialized = false

--- Pending changes counter for auto-commit
local pending_changes = 0

--- Default configuration
local DEFAULT_CONFIG = {
  enabled = true,
  auto_learn = true,
  auto_commit = true,
  commit_threshold = 10,
  max_nodes = 5000,
  max_deltas = 500,
  prune = {
    enabled = true,
    threshold = 0.1,
    unused_days = 90,
  },
  output = {
    max_tokens = 4000,
    format = "compact",
  },
}

--- Initialize brain system
---@param opts? BrainConfig Configuration options
function M.setup(opts)
  config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})

  if not config.enabled then
    return
  end

  -- Ensure storage directories
  storage.ensure_dirs()

  -- Initialize meta if not exists
  storage.get_meta()

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

--- Learn from an event
---@param event LearnEvent Learning event
---@return string|nil Node ID if created
function M.learn(event)
  if not M.is_initialized() or not config.auto_learn then
    return nil
  end

  local learners = require("codetyper.brain.learners")
  local node_id = learners.process(event)

  if node_id then
    pending_changes = pending_changes + 1

    -- Auto-commit if threshold reached
    if config.auto_commit and pending_changes >= config.commit_threshold then
      M.commit("Auto-commit: " .. pending_changes .. " changes")
      pending_changes = 0
    end
  end

  return node_id
end

--- Query relevant knowledge for context
---@param opts QueryOpts Query options
---@return QueryResult
function M.query(opts)
  if not M.is_initialized() then
    return { nodes = {}, edges = {}, stats = {}, truncated = false }
  end

  local query_engine = require("codetyper.brain.graph.query")
  return query_engine.execute(opts)
end

--- Get LLM-optimized context string
---@param opts? QueryOpts Query options
---@return string Formatted context
function M.get_context_for_llm(opts)
  if not M.is_initialized() then
    return ""
  end

  opts = opts or {}
  opts.max_tokens = opts.max_tokens or config.output.max_tokens

  local result = M.query(opts)
  local formatter = require("codetyper.brain.output.formatter")

  if config.output.format == "json" then
    return formatter.to_json(result, opts)
  else
    return formatter.to_compact(result, opts)
  end
end

--- Create a delta commit
---@param message string Commit message
---@return string|nil Delta hash
function M.commit(message)
  if not M.is_initialized() then
    return nil
  end

  local delta_mgr = require("codetyper.brain.delta")
  return delta_mgr.commit(message)
end

--- Rollback to a previous delta
---@param delta_hash string Target delta hash
---@return boolean Success
function M.rollback(delta_hash)
  if not M.is_initialized() then
    return false
  end

  local delta_mgr = require("codetyper.brain.delta")
  return delta_mgr.rollback(delta_hash)
end

--- Get delta history
---@param limit? number Max entries
---@return Delta[]
function M.get_history(limit)
  if not M.is_initialized() then
    return {}
  end

  local delta_mgr = require("codetyper.brain.delta")
  return delta_mgr.get_history(limit or 50)
end

--- Prune low-value nodes
---@param opts? table Prune options
---@return number Number of pruned nodes
function M.prune(opts)
  if not M.is_initialized() or not config.prune.enabled then
    return 0
  end

  opts = vim.tbl_extend("force", {
    threshold = config.prune.threshold,
    unused_days = config.prune.unused_days,
  }, opts or {})

  local graph = require("codetyper.brain.graph")
  return graph.prune(opts)
end

--- Export brain state
---@return table|nil Exported data
function M.export()
  if not M.is_initialized() then
    return nil
  end

  return {
    schema = types.SCHEMA_VERSION,
    meta = storage.get_meta(),
    graph = storage.get_graph(),
    nodes = {
      patterns = storage.get_nodes("patterns"),
      corrections = storage.get_nodes("corrections"),
      decisions = storage.get_nodes("decisions"),
      conventions = storage.get_nodes("conventions"),
      feedback = storage.get_nodes("feedback"),
      sessions = storage.get_nodes("sessions"),
    },
    indices = {
      by_file = storage.get_index("by_file"),
      by_time = storage.get_index("by_time"),
      by_symbol = storage.get_index("by_symbol"),
    },
  }
end

--- Import brain state
---@param data table Exported data
---@return boolean Success
function M.import(data)
  if not data or data.schema ~= types.SCHEMA_VERSION then
    return false
  end

  storage.ensure_dirs()

  -- Import nodes
  if data.nodes then
    for node_type, nodes in pairs(data.nodes) do
      storage.save_nodes(node_type, nodes)
    end
  end

  -- Import graph
  if data.graph then
    storage.save_graph(data.graph)
  end

  -- Import indices
  if data.indices then
    for index_type, index_data in pairs(data.indices) do
      storage.save_index(index_type, index_data)
    end
  end

  -- Import meta last
  if data.meta then
    for k, v in pairs(data.meta) do
      storage.update_meta({ [k] = v })
    end
  end

  storage.flush_all()
  return true
end

--- Get stats about the brain
---@return table Stats
function M.stats()
  if not M.is_initialized() then
    return {}
  end

  local meta = storage.get_meta()
  return {
    initialized = true,
    node_count = meta.nc,
    edge_count = meta.ec,
    delta_count = meta.dc,
    head = meta.head,
    pending_changes = pending_changes,
  }
end

--- Flush all pending writes to disk
function M.flush()
  storage.flush_all()
end

--- Shutdown brain (call before exit)
function M.shutdown()
  if pending_changes > 0 then
    M.commit("Session end: " .. pending_changes .. " changes")
  end
  storage.flush_all()
  initialized = false
end

return M
