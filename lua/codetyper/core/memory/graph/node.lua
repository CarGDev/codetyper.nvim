--- Brain Graph Node Operations
--- CRUD operations for learning nodes

local storage = require("codetyper.core.memory.storage")
local hash = require("codetyper.core.memory.hash")
local types = require("codetyper.core.memory.types")

local M = {}

--- Pending changes for delta tracking
---@type table[]
M.pending = {}

--- Node type to file mapping
local TYPE_MAP = {
  [types.NODE_TYPES.PATTERN] = "patterns",
  [types.NODE_TYPES.CORRECTION] = "corrections",
  [types.NODE_TYPES.DECISION] = "decisions",
  [types.NODE_TYPES.CONVENTION] = "conventions",
  [types.NODE_TYPES.FEEDBACK] = "feedback",
  [types.NODE_TYPES.SESSION] = "sessions",
  -- Full names for convenience
  patterns = "patterns",
  corrections = "corrections",
  decisions = "decisions",
  conventions = "conventions",
  feedback = "feedback",
  sessions = "sessions",
}

--- Get storage key for node type
---@param node_type string Node type
---@return string Storage key
local function get_storage_key(node_type)
  return TYPE_MAP[node_type] or "patterns"
end

--- Create a new node
---@param node_type NodeType Node type
---@param content NodeContent Content
---@param context? NodeContext Context
---@param opts? table Additional options
---@return Node Created node
function M.create(node_type, content, context, opts)
  opts = opts or {}
  local now = os.time()

  local node = {
    id = hash.node_id(node_type, content.s),
    t = node_type,
    h = hash.compute(content.s .. (content.d or "")),
    c = {
      s = content.s or "",
      d = content.d or content.s or "",
      code = content.code,
      lang = content.lang,
    },
    ctx = context or {},
    sc = {
      w = opts.weight or 0.5,
      u = 0,
      sr = 1.0,
    },
    ts = {
      cr = now,
      up = now,
      lu = now,
    },
    m = {
      src = opts.source or types.SOURCES.AUTO,
      v = 1,
    },
  }

  -- Store node
  local storage_key = get_storage_key(node_type)
  local nodes = storage.get_nodes(storage_key)
  nodes[node.id] = node
  storage.save_nodes(storage_key, nodes)

  -- Update meta
  local meta = storage.get_meta()
  storage.update_meta({ nc = meta.nc + 1 })

  -- Update indices
  M.update_indices(node, "add")

  -- Track pending change
  table.insert(M.pending, {
    op = types.DELTA_OPS.ADD,
    path = "nodes." .. storage_key .. "." .. node.id,
    ah = node.h,
  })

  return node
end

--- Get a node by ID
---@param node_id string Node ID
---@return Node|nil
function M.get(node_id)
  -- Parse node type from ID (n_<type>_<timestamp>_<hash>)
  local parts = vim.split(node_id, "_")
  if #parts < 3 then
    return nil
  end

  local node_type = parts[2]
  local storage_key = get_storage_key(node_type)
  local nodes = storage.get_nodes(storage_key)

  return nodes[node_id]
end

--- Update a node
---@param node_id string Node ID
---@param updates table Partial updates
---@return Node|nil Updated node
function M.update(node_id, updates)
  local node = M.get(node_id)
  if not node then
    return nil
  end

  local before_hash = node.h

  -- Apply updates
  if updates.c then
    node.c = vim.tbl_deep_extend("force", node.c, updates.c)
  end
  if updates.ctx then
    node.ctx = vim.tbl_deep_extend("force", node.ctx, updates.ctx)
  end
  if updates.sc then
    node.sc = vim.tbl_deep_extend("force", node.sc, updates.sc)
  end

  -- Update timestamps and hash
  node.ts.up = os.time()
  node.h = hash.compute((node.c.s or "") .. (node.c.d or ""))
  node.m.v = (node.m.v or 0) + 1

  -- Save
  local storage_key = get_storage_key(node.t)
  local nodes = storage.get_nodes(storage_key)
  nodes[node_id] = node
  storage.save_nodes(storage_key, nodes)

  -- Update indices if context changed
  if updates.ctx then
    M.update_indices(node, "update")
  end

  -- Track pending change
  table.insert(M.pending, {
    op = types.DELTA_OPS.MODIFY,
    path = "nodes." .. storage_key .. "." .. node_id,
    bh = before_hash,
    ah = node.h,
  })

  return node
end

--- Delete a node
---@param node_id string Node ID
---@return boolean Success
function M.delete(node_id)
  local node = M.get(node_id)
  if not node then
    return false
  end

  local storage_key = get_storage_key(node.t)
  local nodes = storage.get_nodes(storage_key)

  if not nodes[node_id] then
    return false
  end

  local before_hash = node.h
  nodes[node_id] = nil
  storage.save_nodes(storage_key, nodes)

  -- Update meta
  local meta = storage.get_meta()
  storage.update_meta({ nc = math.max(0, meta.nc - 1) })

  -- Update indices
  M.update_indices(node, "delete")

  -- Track pending change
  table.insert(M.pending, {
    op = types.DELTA_OPS.DELETE,
    path = "nodes." .. storage_key .. "." .. node_id,
    bh = before_hash,
  })

  return true
end

--- Find nodes by criteria
---@param criteria table Search criteria
---@return Node[]
function M.find(criteria)
  local results = {}

  local node_types = criteria.types or vim.tbl_values(types.NODE_TYPES)

  for _, node_type in ipairs(node_types) do
    local storage_key = get_storage_key(node_type)
    local nodes = storage.get_nodes(storage_key)

    for _, node in pairs(nodes) do
      local matches = true

      -- Filter by file
      if criteria.file and node.ctx.f ~= criteria.file then
        matches = false
      end

      -- Filter by min weight
      if criteria.min_weight and node.sc.w < criteria.min_weight then
        matches = false
      end

      -- Filter by since timestamp
      if criteria.since and node.ts.cr < criteria.since then
        matches = false
      end

      -- Filter by content match
      if criteria.query then
        local query_lower = criteria.query:lower()
        local summary_lower = (node.c.s or ""):lower()
        local detail_lower = (node.c.d or ""):lower()
        if not summary_lower:find(query_lower, 1, true) and not detail_lower:find(query_lower, 1, true) then
          matches = false
        end
      end

      if matches then
        table.insert(results, node)
      end
    end
  end

  -- Sort by relevance (weight * recency)
  table.sort(results, function(a, b)
    local score_a = a.sc.w * (1 / (1 + (os.time() - a.ts.lu) / 86400))
    local score_b = b.sc.w * (1 / (1 + (os.time() - b.ts.lu) / 86400))
    return score_a > score_b
  end)

  -- Apply limit
  if criteria.limit and #results > criteria.limit then
    local limited = {}
    for i = 1, criteria.limit do
      limited[i] = results[i]
    end
    return limited
  end

  return results
end

--- Record usage of a node
---@param node_id string Node ID
---@param success? boolean Was the usage successful
function M.record_usage(node_id, success)
  local node = M.get(node_id)
  if not node then
    return
  end

  -- Update usage stats
  node.sc.u = node.sc.u + 1
  node.ts.lu = os.time()

  -- Update success rate
  if success ~= nil then
    local total = node.sc.u
    local successes = node.sc.sr * (total - 1) + (success and 1 or 0)
    node.sc.sr = successes / total
  end

  -- Increase weight slightly for frequently used nodes
  if node.sc.u > 5 then
    node.sc.w = math.min(1.0, node.sc.w + 0.01)
  end

  -- Save (direct save, no pending change tracking for usage)
  local storage_key = get_storage_key(node.t)
  local nodes = storage.get_nodes(storage_key)
  nodes[node_id] = node
  storage.save_nodes(storage_key, nodes)
end

--- Update indices for a node
---@param node Node The node
---@param op "add"|"update"|"delete" Operation type
function M.update_indices(node, op)
  -- File index
  if node.ctx.f then
    local by_file = storage.get_index("by_file")

    if op == "delete" then
      if by_file[node.ctx.f] then
        by_file[node.ctx.f] = vim.tbl_filter(function(id)
          return id ~= node.id
        end, by_file[node.ctx.f])
      end
    else
      by_file[node.ctx.f] = by_file[node.ctx.f] or {}
      if not vim.tbl_contains(by_file[node.ctx.f], node.id) then
        table.insert(by_file[node.ctx.f], node.id)
      end
    end

    storage.save_index("by_file", by_file)
  end

  -- Symbol index
  if node.ctx.sym then
    local by_symbol = storage.get_index("by_symbol")

    for _, sym in ipairs(node.ctx.sym) do
      if op == "delete" then
        if by_symbol[sym] then
          by_symbol[sym] = vim.tbl_filter(function(id)
            return id ~= node.id
          end, by_symbol[sym])
        end
      else
        by_symbol[sym] = by_symbol[sym] or {}
        if not vim.tbl_contains(by_symbol[sym], node.id) then
          table.insert(by_symbol[sym], node.id)
        end
      end
    end

    storage.save_index("by_symbol", by_symbol)
  end

  -- Time index (daily buckets)
  local day = os.date("%Y-%m-%d", node.ts.cr)
  local by_time = storage.get_index("by_time")

  if op == "delete" then
    if by_time[day] then
      by_time[day] = vim.tbl_filter(function(id)
        return id ~= node.id
      end, by_time[day])
    end
  elseif op == "add" then
    by_time[day] = by_time[day] or {}
    if not vim.tbl_contains(by_time[day], node.id) then
      table.insert(by_time[day], node.id)
    end
  end

  storage.save_index("by_time", by_time)
end

--- Get pending changes and clear
---@return table[] Pending changes
function M.get_and_clear_pending()
  local changes = M.pending
  M.pending = {}
  return changes
end

--- Merge two similar nodes
---@param node_id_1 string First node ID
---@param node_id_2 string Second node ID (will be deleted)
---@return Node|nil Merged node
function M.merge(node_id_1, node_id_2)
  local node1 = M.get(node_id_1)
  local node2 = M.get(node_id_2)

  if not node1 or not node2 then
    return nil
  end

  -- Merge content (keep longer detail)
  local merged_detail = #node1.c.d > #node2.c.d and node1.c.d or node2.c.d

  -- Merge scores (combine weights and usage)
  local merged_weight = (node1.sc.w + node2.sc.w) / 2
  local merged_usage = node1.sc.u + node2.sc.u

  M.update(node_id_1, {
    c = { d = merged_detail },
    sc = { w = merged_weight, u = merged_usage },
  })

  -- Delete the second node
  M.delete(node_id_2)

  return M.get(node_id_1)
end

return M
