--- Brain Graph Edge Operations
--- CRUD operations for node connections

local storage = require("codetyper.brain.storage")
local hash = require("codetyper.brain.hash")
local types = require("codetyper.brain.types")

local M = {}

--- Pending changes for delta tracking
---@type table[]
M.pending = {}

--- Create a new edge between nodes
---@param source_id string Source node ID
---@param target_id string Target node ID
---@param edge_type EdgeType Edge type
---@param props? EdgeProps Edge properties
---@return Edge|nil Created edge
function M.create(source_id, target_id, edge_type, props)
  props = props or {}

  local edge = {
    id = hash.edge_id(source_id, target_id),
    s = source_id,
    t = target_id,
    ty = edge_type,
    p = {
      w = props.w or 0.5,
      dir = props.dir or "bi",
      r = props.r,
    },
    ts = os.time(),
  }

  -- Update adjacency lists
  local graph = storage.get_graph()

  -- Forward adjacency
  graph.adj[source_id] = graph.adj[source_id] or {}
  graph.adj[source_id][edge_type] = graph.adj[source_id][edge_type] or {}

  -- Check for duplicate
  if vim.tbl_contains(graph.adj[source_id][edge_type], target_id) then
    -- Edge exists, strengthen it instead
    return M.strengthen(source_id, target_id, edge_type)
  end

  table.insert(graph.adj[source_id][edge_type], target_id)

  -- Reverse adjacency
  graph.radj[target_id] = graph.radj[target_id] or {}
  graph.radj[target_id][edge_type] = graph.radj[target_id][edge_type] or {}
  table.insert(graph.radj[target_id][edge_type], source_id)

  -- Store edge properties separately (for weight/metadata)
  graph.edges = graph.edges or {}
  graph.edges[edge.id] = edge

  storage.save_graph(graph)

  -- Update meta
  local meta = storage.get_meta()
  storage.update_meta({ ec = meta.ec + 1 })

  -- Track pending change
  table.insert(M.pending, {
    op = types.DELTA_OPS.ADD,
    path = "graph.edges." .. edge.id,
    ah = hash.compute_table(edge),
  })

  return edge
end

--- Get edge by source and target
---@param source_id string Source node ID
---@param target_id string Target node ID
---@param edge_type? EdgeType Optional edge type filter
---@return Edge|nil
function M.get(source_id, target_id, edge_type)
  local graph = storage.get_graph()
  local edge_id = hash.edge_id(source_id, target_id)

  if not graph.edges or not graph.edges[edge_id] then
    return nil
  end

  local edge = graph.edges[edge_id]

  if edge_type and edge.ty ~= edge_type then
    return nil
  end

  return edge
end

--- Get all edges for a node
---@param node_id string Node ID
---@param edge_types? EdgeType[] Edge types to include
---@param direction? "out"|"in"|"both" Direction (default: "out")
---@return Edge[]
function M.get_edges(node_id, edge_types, direction)
  direction = direction or "out"
  local graph = storage.get_graph()
  local results = {}

  edge_types = edge_types or vim.tbl_values(types.EDGE_TYPES)

  -- Outgoing edges
  if direction == "out" or direction == "both" then
    local adj = graph.adj[node_id]
    if adj then
      for _, edge_type in ipairs(edge_types) do
        local targets = adj[edge_type] or {}
        for _, target_id in ipairs(targets) do
          local edge_id = hash.edge_id(node_id, target_id)
          if graph.edges and graph.edges[edge_id] then
            table.insert(results, graph.edges[edge_id])
          end
        end
      end
    end
  end

  -- Incoming edges
  if direction == "in" or direction == "both" then
    local radj = graph.radj[node_id]
    if radj then
      for _, edge_type in ipairs(edge_types) do
        local sources = radj[edge_type] or {}
        for _, source_id in ipairs(sources) do
          local edge_id = hash.edge_id(source_id, node_id)
          if graph.edges and graph.edges[edge_id] then
            table.insert(results, graph.edges[edge_id])
          end
        end
      end
    end
  end

  return results
end

--- Get neighbor node IDs
---@param node_id string Node ID
---@param edge_types? EdgeType[] Edge types to follow
---@param direction? "out"|"in"|"both" Direction
---@return string[] Neighbor node IDs
function M.get_neighbors(node_id, edge_types, direction)
  direction = direction or "out"
  local graph = storage.get_graph()
  local neighbors = {}

  edge_types = edge_types or vim.tbl_values(types.EDGE_TYPES)

  -- Outgoing
  if direction == "out" or direction == "both" then
    local adj = graph.adj[node_id]
    if adj then
      for _, edge_type in ipairs(edge_types) do
        for _, target in ipairs(adj[edge_type] or {}) do
          if not vim.tbl_contains(neighbors, target) then
            table.insert(neighbors, target)
          end
        end
      end
    end
  end

  -- Incoming
  if direction == "in" or direction == "both" then
    local radj = graph.radj[node_id]
    if radj then
      for _, edge_type in ipairs(edge_types) do
        for _, source in ipairs(radj[edge_type] or {}) do
          if not vim.tbl_contains(neighbors, source) then
            table.insert(neighbors, source)
          end
        end
      end
    end
  end

  return neighbors
end

--- Delete an edge
---@param source_id string Source node ID
---@param target_id string Target node ID
---@param edge_type? EdgeType Edge type (deletes all if nil)
---@return boolean Success
function M.delete(source_id, target_id, edge_type)
  local graph = storage.get_graph()
  local edge_id = hash.edge_id(source_id, target_id)

  if not graph.edges or not graph.edges[edge_id] then
    return false
  end

  local edge = graph.edges[edge_id]

  if edge_type and edge.ty ~= edge_type then
    return false
  end

  local before_hash = hash.compute_table(edge)

  -- Remove from adjacency
  if graph.adj[source_id] and graph.adj[source_id][edge.ty] then
    graph.adj[source_id][edge.ty] = vim.tbl_filter(function(id)
      return id ~= target_id
    end, graph.adj[source_id][edge.ty])
  end

  -- Remove from reverse adjacency
  if graph.radj[target_id] and graph.radj[target_id][edge.ty] then
    graph.radj[target_id][edge.ty] = vim.tbl_filter(function(id)
      return id ~= source_id
    end, graph.radj[target_id][edge.ty])
  end

  -- Remove edge data
  graph.edges[edge_id] = nil

  storage.save_graph(graph)

  -- Update meta
  local meta = storage.get_meta()
  storage.update_meta({ ec = math.max(0, meta.ec - 1) })

  -- Track pending change
  table.insert(M.pending, {
    op = types.DELTA_OPS.DELETE,
    path = "graph.edges." .. edge_id,
    bh = before_hash,
  })

  return true
end

--- Delete all edges for a node
---@param node_id string Node ID
---@return number Number of deleted edges
function M.delete_all(node_id)
  local edges = M.get_edges(node_id, nil, "both")
  local count = 0

  for _, edge in ipairs(edges) do
    if M.delete(edge.s, edge.t, edge.ty) then
      count = count + 1
    end
  end

  return count
end

--- Strengthen an existing edge
---@param source_id string Source node ID
---@param target_id string Target node ID
---@param edge_type EdgeType Edge type
---@return Edge|nil Updated edge
function M.strengthen(source_id, target_id, edge_type)
  local graph = storage.get_graph()
  local edge_id = hash.edge_id(source_id, target_id)

  if not graph.edges or not graph.edges[edge_id] then
    return nil
  end

  local edge = graph.edges[edge_id]

  if edge.ty ~= edge_type then
    return nil
  end

  -- Increase weight (diminishing returns)
  edge.p.w = math.min(1.0, edge.p.w + (1 - edge.p.w) * 0.1)
  edge.ts = os.time()

  graph.edges[edge_id] = edge
  storage.save_graph(graph)

  return edge
end

--- Find path between two nodes
---@param from_id string Start node ID
---@param to_id string End node ID
---@param max_depth? number Maximum depth (default: 5)
---@return table|nil Path info {nodes: string[], edges: Edge[], found: boolean}
function M.find_path(from_id, to_id, max_depth)
  max_depth = max_depth or 5

  -- BFS
  local queue = { { id = from_id, path = {}, edges = {} } }
  local visited = { [from_id] = true }

  while #queue > 0 do
    local current = table.remove(queue, 1)

    if current.id == to_id then
      table.insert(current.path, to_id)
      return {
        nodes = current.path,
        edges = current.edges,
        found = true,
      }
    end

    if #current.path >= max_depth then
      goto continue
    end

    -- Get all neighbors
    local edges = M.get_edges(current.id, nil, "both")

    for _, edge in ipairs(edges) do
      local neighbor = edge.s == current.id and edge.t or edge.s

      if not visited[neighbor] then
        visited[neighbor] = true

        local new_path = vim.list_extend({}, current.path)
        table.insert(new_path, current.id)

        local new_edges = vim.list_extend({}, current.edges)
        table.insert(new_edges, edge)

        table.insert(queue, {
          id = neighbor,
          path = new_path,
          edges = new_edges,
        })
      end
    end

    ::continue::
  end

  return { nodes = {}, edges = {}, found = false }
end

--- Get pending changes and clear
---@return table[] Pending changes
function M.get_and_clear_pending()
  local changes = M.pending
  M.pending = {}
  return changes
end

--- Check if two nodes are connected
---@param node_id_1 string First node ID
---@param node_id_2 string Second node ID
---@param edge_type? EdgeType Edge type filter
---@return boolean
function M.are_connected(node_id_1, node_id_2, edge_type)
  local edge = M.get(node_id_1, node_id_2, edge_type)
  if edge then
    return true
  end
  -- Check reverse
  edge = M.get(node_id_2, node_id_1, edge_type)
  return edge ~= nil
end

return M
