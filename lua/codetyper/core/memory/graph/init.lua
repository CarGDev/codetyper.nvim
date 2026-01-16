--- Brain Graph Coordinator
--- High-level graph operations

local node = require("codetyper.core.memory.graph.node")
local edge = require("codetyper.core.memory.graph.edge")
local query = require("codetyper.core.memory.graph.query")
local storage = require("codetyper.core.memory.storage")
local types = require("codetyper.core.memory.types")

local M = {}

-- Re-export submodules
M.node = node
M.edge = edge
M.query = query

--- Add a learning with automatic edge creation
---@param node_type NodeType Node type
---@param content NodeContent Content
---@param context? NodeContext Context
---@param related_ids? string[] Related node IDs
---@return Node Created node
function M.add_learning(node_type, content, context, related_ids)
  -- Create the node
  local new_node = node.create(node_type, content, context)

  -- Create edges to related nodes
  if related_ids then
    for _, related_id in ipairs(related_ids) do
      local related_node = node.get(related_id)
      if related_node then
        -- Determine edge type based on relationship
        local edge_type = types.EDGE_TYPES.SEMANTIC

        -- If same file, use file edge
        if context and context.f and related_node.ctx and related_node.ctx.f == context.f then
          edge_type = types.EDGE_TYPES.FILE
        end

        edge.create(new_node.id, related_id, edge_type, {
          w = 0.5,
          r = "Related learning",
        })
      end
    end
  end

  -- Find and link to similar existing nodes
  local similar = query.semantic_search(content.s, 5)
  for _, sim_node in ipairs(similar) do
    if sim_node.id ~= new_node.id then
      -- Create semantic edge if similarity is high enough
      local sim_score = query.compute_relevance(sim_node, { query = content.s })
      if sim_score > 0.5 then
        edge.create(new_node.id, sim_node.id, types.EDGE_TYPES.SEMANTIC, {
          w = sim_score,
          r = "Semantic similarity",
        })
      end
    end
  end

  return new_node
end

--- Remove a learning and its edges
---@param node_id string Node ID to remove
---@return boolean Success
function M.remove_learning(node_id)
  -- Delete all edges first
  edge.delete_all(node_id)

  -- Delete the node
  return node.delete(node_id)
end

--- Prune low-value nodes
---@param opts? table Prune options
---@return number Number of pruned nodes
function M.prune(opts)
  opts = opts or {}
  local threshold = opts.threshold or 0.1
  local unused_days = opts.unused_days or 90
  local now = os.time()
  local cutoff = now - (unused_days * 86400)

  local pruned = 0

  -- Find nodes to prune
  for _, node_type in pairs(types.NODE_TYPES) do
    local nodes_to_prune = node.find({
      types = { node_type },
      min_weight = 0, -- Get all
    })

    for _, n in ipairs(nodes_to_prune) do
      local should_prune = false

      -- Prune if weight below threshold and not used recently
      if n.sc.w < threshold and (n.ts.lu or n.ts.up) < cutoff then
        should_prune = true
      end

      -- Prune if never used and old
      if n.sc.u == 0 and n.ts.cr < cutoff then
        should_prune = true
      end

      if should_prune then
        if M.remove_learning(n.id) then
          pruned = pruned + 1
        end
      end
    end
  end

  return pruned
end

--- Get all pending changes from nodes and edges
---@return table[] Combined pending changes
function M.get_pending_changes()
  local changes = {}

  -- Get node changes
  local node_changes = node.get_and_clear_pending()
  for _, change in ipairs(node_changes) do
    table.insert(changes, change)
  end

  -- Get edge changes
  local edge_changes = edge.get_and_clear_pending()
  for _, change in ipairs(edge_changes) do
    table.insert(changes, change)
  end

  return changes
end

--- Get graph statistics
---@return table Stats
function M.stats()
  local meta = storage.get_meta()

  -- Count nodes by type
  local by_type = {}
  for _, node_type in pairs(types.NODE_TYPES) do
    local nodes = storage.get_nodes(node_type .. "s")
    by_type[node_type] = vim.tbl_count(nodes)
  end

  -- Count edges by type
  local graph = storage.get_graph()
  local edges_by_type = {}
  if graph.edges then
    for _, e in pairs(graph.edges) do
      edges_by_type[e.ty] = (edges_by_type[e.ty] or 0) + 1
    end
  end

  return {
    node_count = meta.nc,
    edge_count = meta.ec,
    delta_count = meta.dc,
    nodes_by_type = by_type,
    edges_by_type = edges_by_type,
  }
end

--- Create temporal edge between nodes created in sequence
---@param node_ids string[] Node IDs in temporal order
function M.link_temporal(node_ids)
  for i = 1, #node_ids - 1 do
    edge.create(node_ids[i], node_ids[i + 1], types.EDGE_TYPES.TEMPORAL, {
      w = 0.7,
      dir = "fwd",
      r = "Temporal sequence",
    })
  end
end

--- Create causal edge (this caused that)
---@param cause_id string Cause node ID
---@param effect_id string Effect node ID
---@param reason? string Reason description
function M.link_causal(cause_id, effect_id, reason)
  edge.create(cause_id, effect_id, types.EDGE_TYPES.CAUSAL, {
    w = 0.8,
    dir = "fwd",
    r = reason or "Caused by",
  })
end

--- Mark a node as superseded by another
---@param old_id string Old node ID
---@param new_id string New node ID
function M.supersede(old_id, new_id)
  edge.create(old_id, new_id, types.EDGE_TYPES.SUPERSEDES, {
    w = 1.0,
    dir = "fwd",
    r = "Superseded by newer learning",
  })

  -- Reduce weight of old node
  local old_node = node.get(old_id)
  if old_node then
    node.update(old_id, {
      sc = { w = old_node.sc.w * 0.5 },
    })
  end
end

return M
