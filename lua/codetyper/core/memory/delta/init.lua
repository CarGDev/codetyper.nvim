--- Brain Delta Coordinator
--- Git-like versioning system for brain state

local storage = require("codetyper.core.memory.storage")
local commit_mod = require("codetyper.core.memory.delta.commit")
local diff_mod = require("codetyper.core.memory.delta.diff")
local types = require("codetyper.core.memory.types")

local M = {}

-- Re-export submodules
M.commit = commit_mod
M.diff = diff_mod

--- Create a commit from pending graph changes
---@param message string Commit message
---@param trigger? string Trigger source
---@return string|nil Delta hash
function M.commit(message, trigger)
  local graph = require("codetyper.core.memory.graph")
  local changes = graph.get_pending_changes()

  if #changes == 0 then
    return nil
  end

  local delta = commit_mod.create(changes, message, trigger or "auto")
  if delta then
    return delta.h
  end

  return nil
end

--- Rollback to a specific delta
---@param target_hash string Target delta hash
---@return boolean Success
function M.rollback(target_hash)
  local current_hash = storage.get_head()
  if not current_hash then
    return false
  end

  if current_hash == target_hash then
    return true -- Already at target
  end

  -- Get path from target to current
  local deltas_to_reverse = {}
  local current = current_hash

  while current and current ~= target_hash do
    local delta = commit_mod.get(current)
    if not delta then
      return false -- Broken chain
    end
    table.insert(deltas_to_reverse, delta)
    current = delta.p
  end

  if current ~= target_hash then
    return false -- Target not in ancestry
  end

  -- Apply reverse changes
  for _, delta in ipairs(deltas_to_reverse) do
    local reverse_changes = commit_mod.compute_reverse(delta)
    M.apply_changes(reverse_changes)
  end

  -- Update HEAD
  storage.set_head(target_hash)

  -- Create a rollback commit
  commit_mod.create({
    {
      op = types.DELTA_OPS.MODIFY,
      path = "meta.head",
      bh = current_hash,
      ah = target_hash,
    },
  }, "Rollback to " .. target_hash:sub(1, 8), "rollback")

  return true
end

--- Apply changes to current state
---@param changes table[] Changes to apply
function M.apply_changes(changes)
  local node_mod = require("codetyper.core.memory.graph.node")

  for _, change in ipairs(changes) do
    local parts = vim.split(change.path, ".", { plain = true })

    if parts[1] == "nodes" and #parts >= 3 then
      local node_type = parts[2]
      local node_id = parts[3]

      if change.op == types.DELTA_OPS.ADD then
        -- Node was added, need to delete for reverse
        node_mod.delete(node_id)
      elseif change.op == types.DELTA_OPS.DELETE then
        -- Node was deleted, would need original data to restore
        -- This is a limitation - we'd need content storage
      elseif change.op == types.DELTA_OPS.MODIFY then
        -- Apply diff if available
        if change.diff then
          local node = node_mod.get(node_id)
          if node then
            local updated = diff_mod.apply(node, change.diff)
            -- Direct update without tracking
            local nodes = storage.get_nodes(node_type)
            nodes[node_id] = updated
            storage.save_nodes(node_type, nodes)
          end
        end
      end
    elseif parts[1] == "graph" then
      -- Handle graph/edge changes
      local edge_mod = require("codetyper.core.memory.graph.edge")
      if parts[2] == "edges" and #parts >= 3 then
        local edge_id = parts[3]
        if change.op == types.DELTA_OPS.ADD then
          -- Edge was added, delete for reverse
          -- Parse edge_id to get source/target
          local graph = storage.get_graph()
          if graph.edges and graph.edges[edge_id] then
            local edge = graph.edges[edge_id]
            edge_mod.delete(edge.s, edge.t, edge.ty)
          end
        end
      end
    end
  end
end

--- Get delta history
---@param limit? number Max entries
---@return Delta[]
function M.get_history(limit)
  return commit_mod.get_history(limit)
end

--- Get formatted log
---@param limit? number Max entries
---@return string[] Log lines
function M.log(limit)
  local history = M.get_history(limit or 20)
  local lines = {}

  for _, delta in ipairs(history) do
    local formatted = commit_mod.format(delta)
    for _, line in ipairs(formatted) do
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end

  return lines
end

--- Get current HEAD hash
---@return string|nil
function M.head()
  return storage.get_head()
end

--- Check if there are uncommitted changes
---@return boolean
function M.has_pending()
  local graph = require("codetyper.core.memory.graph")
  local node_pending = require("codetyper.core.memory.graph.node").pending
  local edge_pending = require("codetyper.core.memory.graph.edge").pending
  return #node_pending > 0 or #edge_pending > 0
end

--- Get status (like git status)
---@return table Status info
function M.status()
  local node_pending = require("codetyper.core.memory.graph.node").pending
  local edge_pending = require("codetyper.core.memory.graph.edge").pending

  local adds = 0
  local mods = 0
  local dels = 0

  for _, change in ipairs(node_pending) do
    if change.op == types.DELTA_OPS.ADD then
      adds = adds + 1
    elseif change.op == types.DELTA_OPS.MODIFY then
      mods = mods + 1
    elseif change.op == types.DELTA_OPS.DELETE then
      dels = dels + 1
    end
  end

  for _, change in ipairs(edge_pending) do
    if change.op == types.DELTA_OPS.ADD then
      adds = adds + 1
    elseif change.op == types.DELTA_OPS.DELETE then
      dels = dels + 1
    end
  end

  return {
    head = storage.get_head(),
    pending = {
      adds = adds,
      modifies = mods,
      deletes = dels,
      total = adds + mods + dels,
    },
    clean = (adds + mods + dels) == 0,
  }
end

--- Prune old deltas
---@param keep number Number of recent deltas to keep
---@return number Number of pruned deltas
function M.prune_history(keep)
  keep = keep or 100
  local history = M.get_history(1000) -- Get all

  if #history <= keep then
    return 0
  end

  local pruned = 0
  local brain_dir = storage.get_brain_dir()

  for i = keep + 1, #history do
    local delta = history[i]
    local filepath = brain_dir .. "/deltas/objects/" .. delta.h .. ".json"
    if os.remove(filepath) then
      pruned = pruned + 1
    end
  end

  -- Update meta
  local meta = storage.get_meta()
  storage.update_meta({ dc = math.max(0, meta.dc - pruned) })

  return pruned
end

--- Reset to initial state (dangerous!)
---@return boolean Success
function M.reset()
  -- Clear all nodes
  for _, node_type in pairs(types.NODE_TYPES) do
    storage.save_nodes(node_type .. "s", {})
  end

  -- Clear graph
  storage.save_graph({ adj = {}, radj = {}, edges = {} })

  -- Clear indices
  storage.save_index("by_file", {})
  storage.save_index("by_time", {})
  storage.save_index("by_symbol", {})

  -- Reset meta
  storage.update_meta({
    head = nil,
    nc = 0,
    ec = 0,
    dc = 0,
  })

  -- Clear pending
  require("codetyper.core.memory.graph.node").pending = {}
  require("codetyper.core.memory.graph.edge").pending = {}

  storage.flush_all()
  return true
end

return M
