--- Brain Graph Query Engine
--- Multi-dimensional traversal and relevance scoring

local storage = require("codetyper.brain.storage")
local types = require("codetyper.brain.types")

local M = {}

--- Lazy load dependencies to avoid circular requires
local function get_node_module()
  return require("codetyper.brain.graph.node")
end

local function get_edge_module()
  return require("codetyper.brain.graph.edge")
end

--- Compute text similarity (simple keyword matching)
---@param text1 string First text
---@param text2 string Second text
---@return number Similarity score (0-1)
local function text_similarity(text1, text2)
  if not text1 or not text2 then
    return 0
  end

  text1 = text1:lower()
  text2 = text2:lower()

  -- Extract words
  local words1 = {}
  for word in text1:gmatch("%w+") do
    words1[word] = true
  end

  local words2 = {}
  for word in text2:gmatch("%w+") do
    words2[word] = true
  end

  -- Count matches
  local matches = 0
  local total = 0

  for word in pairs(words1) do
    total = total + 1
    if words2[word] then
      matches = matches + 1
    end
  end

  for word in pairs(words2) do
    if not words1[word] then
      total = total + 1
    end
  end

  if total == 0 then
    return 0
  end

  return matches / total
end

--- Compute relevance score for a node
---@param node Node Node to score
---@param opts QueryOpts Query options
---@return number Relevance score (0-1)
function M.compute_relevance(node, opts)
  local score = 0
  local weights = {
    content_match = 0.30,
    recency = 0.20,
    usage = 0.15,
    weight = 0.15,
    connection_density = 0.10,
    success_rate = 0.10,
  }

  -- Content similarity
  if opts.query then
    local summary = node.c.s or ""
    local detail = node.c.d or ""
    local similarity = math.max(text_similarity(opts.query, summary), text_similarity(opts.query, detail) * 0.8)
    score = score + (similarity * weights.content_match)
  else
    score = score + weights.content_match * 0.5 -- Base score if no query
  end

  -- Recency decay (exponential with 30-day half-life)
  local age_days = (os.time() - (node.ts.lu or node.ts.up)) / 86400
  local recency = math.exp(-age_days / 30)
  score = score + (recency * weights.recency)

  -- Usage frequency (normalized)
  local usage = math.min(node.sc.u / 10, 1.0)
  score = score + (usage * weights.usage)

  -- Node weight
  score = score + (node.sc.w * weights.weight)

  -- Connection density
  local edge_mod = get_edge_module()
  local connections = #edge_mod.get_edges(node.id, nil, "both")
  local density = math.min(connections / 5, 1.0)
  score = score + (density * weights.connection_density)

  -- Success rate
  score = score + (node.sc.sr * weights.success_rate)

  return score
end

--- Traverse graph from seed nodes (basic traversal)
---@param seed_ids string[] Starting node IDs
---@param depth number Traversal depth
---@param edge_types? EdgeType[] Edge types to follow
---@return table<string, Node> Discovered nodes indexed by ID
local function traverse(seed_ids, depth, edge_types)
  local node_mod = get_node_module()
  local edge_mod = get_edge_module()
  local discovered = {}
  local frontier = seed_ids

  for _ = 1, depth do
    local next_frontier = {}

    for _, node_id in ipairs(frontier) do
      -- Skip if already discovered
      if discovered[node_id] then
        goto continue
      end

      -- Get and store node
      local node = node_mod.get(node_id)
      if node then
        discovered[node_id] = node

        -- Get neighbors
        local neighbors = edge_mod.get_neighbors(node_id, edge_types, "both")
        for _, neighbor_id in ipairs(neighbors) do
          if not discovered[neighbor_id] then
            table.insert(next_frontier, neighbor_id)
          end
        end
      end

      ::continue::
    end

    frontier = next_frontier
    if #frontier == 0 then
      break
    end
  end

  return discovered
end

--- Spreading activation - mimics human associative memory
--- Activation spreads from seed nodes along edges, decaying by weight
--- Nodes accumulate activation from multiple paths (like neural pathways)
---@param seed_activations table<string, number> Initial activations {node_id: activation}
---@param max_iterations number Max spread iterations (default 3)
---@param decay number Activation decay per hop (default 0.5)
---@param threshold number Minimum activation to continue spreading (default 0.1)
---@return table<string, number> Final activations {node_id: accumulated_activation}
local function spreading_activation(seed_activations, max_iterations, decay, threshold)
  local edge_mod = get_edge_module()
  max_iterations = max_iterations or 3
  decay = decay or 0.5
  threshold = threshold or 0.1

  -- Accumulated activation for each node
  local activation = {}
  for node_id, act in pairs(seed_activations) do
    activation[node_id] = act
  end

  -- Current frontier with their activation levels
  local frontier = {}
  for node_id, act in pairs(seed_activations) do
    frontier[node_id] = act
  end

  -- Spread activation iteratively
  for _ = 1, max_iterations do
    local next_frontier = {}

    for source_id, source_activation in pairs(frontier) do
      -- Get all outgoing edges
      local edges = edge_mod.get_edges(source_id, nil, "both")

      for _, edge in ipairs(edges) do
        -- Determine target (could be source or target of edge)
        local target_id = edge.s == source_id and edge.t or edge.s

        -- Calculate spreading activation
        -- Activation = source_activation * edge_weight * decay
        local edge_weight = edge.p and edge.p.w or 0.5
        local spread_amount = source_activation * edge_weight * decay

        -- Only spread if above threshold
        if spread_amount >= threshold then
          -- Accumulate activation (multiple paths add up)
          activation[target_id] = (activation[target_id] or 0) + spread_amount

          -- Add to next frontier if not already processed with higher activation
          if not next_frontier[target_id] or next_frontier[target_id] < spread_amount then
            next_frontier[target_id] = spread_amount
          end
        end
      end
    end

    -- Stop if no more spreading
    if vim.tbl_count(next_frontier) == 0 then
      break
    end

    frontier = next_frontier
  end

  return activation
end

--- Execute a query across all dimensions
---@param opts QueryOpts Query options
---@return QueryResult
function M.execute(opts)
  opts = opts or {}
  local node_mod = get_node_module()
  local results = {
    semantic = {},
    file = {},
    temporal = {},
  }

  -- 1. Semantic traversal (content similarity)
  if opts.query then
    local seed_nodes = node_mod.find({
      query = opts.query,
      types = opts.types,
      limit = 10,
    })

    local seed_ids = vim.tbl_map(function(n)
      return n.id
    end, seed_nodes)
    local depth = opts.depth or 2

    local discovered = traverse(seed_ids, depth, { types.EDGE_TYPES.SEMANTIC })
    for id, node in pairs(discovered) do
      results.semantic[id] = node
    end
  end

  -- 2. File-based traversal
  if opts.file then
    local by_file = storage.get_index("by_file")
    local file_node_ids = by_file[opts.file] or {}

    for _, node_id in ipairs(file_node_ids) do
      local node = node_mod.get(node_id)
      if node then
        results.file[node.id] = node
      end
    end

    -- Also get nodes from related files via edges
    local discovered = traverse(file_node_ids, 1, { types.EDGE_TYPES.FILE })
    for id, node in pairs(discovered) do
      results.file[id] = node
    end
  end

  -- 3. Temporal traversal (recent context)
  if opts.since then
    local by_time = storage.get_index("by_time")
    local now = os.time()

    for day, node_ids in pairs(by_time) do
      -- Parse day to timestamp
      local year, month, day_num = day:match("(%d+)-(%d+)-(%d+)")
      if year then
        local day_ts = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day_num) })
        if day_ts >= opts.since then
          for _, node_id in ipairs(node_ids) do
            local node = node_mod.get(node_id)
            if node then
              results.temporal[node.id] = node
            end
          end
        end
      end
    end

    -- Follow temporal edges
    local temporal_ids = vim.tbl_keys(results.temporal)
    local discovered = traverse(temporal_ids, 1, { types.EDGE_TYPES.TEMPORAL })
    for id, node in pairs(discovered) do
      results.temporal[id] = node
    end
  end

  -- 4. Combine all found nodes and compute seed activations
  local all_nodes = {}
  local seed_activations = {}

  for _, category in pairs(results) do
    for id, node in pairs(category) do
      if not all_nodes[id] then
        all_nodes[id] = node
        -- Compute initial activation based on relevance
        local relevance = M.compute_relevance(node, opts)
        seed_activations[id] = relevance
      end
    end
  end

  -- 5. Apply spreading activation - like human associative memory
  -- Activation spreads from seed nodes along edges, accumulating
  -- Nodes connected to multiple relevant seeds get higher activation
  local final_activations = spreading_activation(
    seed_activations,
    opts.spread_iterations or 3,  -- How far activation spreads
    opts.spread_decay or 0.5,     -- How much activation decays per hop
    opts.spread_threshold or 0.05 -- Minimum activation to continue spreading
  )

  -- 6. Score and rank by combined activation
  local scored = {}
  for id, activation in pairs(final_activations) do
    local node = all_nodes[id] or node_mod.get(id)
    if node then
      all_nodes[id] = node
      -- Final score = spreading activation + base relevance
      local base_relevance = M.compute_relevance(node, opts)
      local final_score = (activation * 0.6) + (base_relevance * 0.4)
      table.insert(scored, { node = node, relevance = final_score, activation = activation })
    end
  end

  table.sort(scored, function(a, b)
    return a.relevance > b.relevance
  end)

  -- 7. Apply limit
  local limit = opts.limit or 50
  local result_nodes = {}
  local truncated = #scored > limit

  for i = 1, math.min(limit, #scored) do
    table.insert(result_nodes, scored[i].node)
  end

  -- 8. Get edges between result nodes
  local edge_mod = get_edge_module()
  local result_edges = {}
  local node_ids = {}
  for _, node in ipairs(result_nodes) do
    node_ids[node.id] = true
  end

  for _, node in ipairs(result_nodes) do
    local edges = edge_mod.get_edges(node.id, nil, "out")
    for _, edge in ipairs(edges) do
      if node_ids[edge.t] then
        table.insert(result_edges, edge)
      end
    end
  end

  return {
    nodes = result_nodes,
    edges = result_edges,
    stats = {
      semantic_count = vim.tbl_count(results.semantic),
      file_count = vim.tbl_count(results.file),
      temporal_count = vim.tbl_count(results.temporal),
      total_scored = #scored,
      seed_nodes = vim.tbl_count(seed_activations),
      activated_nodes = vim.tbl_count(final_activations),
    },
    truncated = truncated,
  }
end

--- Expose spreading activation for direct use
--- Useful for custom activation patterns or debugging
M.spreading_activation = spreading_activation

--- Find nodes by file
---@param filepath string File path
---@param limit? number Max results
---@return Node[]
function M.by_file(filepath, limit)
  local result = M.execute({
    file = filepath,
    limit = limit or 20,
  })
  return result.nodes
end

--- Find nodes by time range
---@param since number Start timestamp
---@param until_ts? number End timestamp
---@param limit? number Max results
---@return Node[]
function M.by_time_range(since, until_ts, limit)
  local node_mod = get_node_module()
  local by_time = storage.get_index("by_time")
  local results = {}

  until_ts = until_ts or os.time()

  for day, node_ids in pairs(by_time) do
    local year, month, day_num = day:match("(%d+)-(%d+)-(%d+)")
    if year then
      local day_ts = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day_num) })
      if day_ts >= since and day_ts <= until_ts then
        for _, node_id in ipairs(node_ids) do
          local node = node_mod.get(node_id)
          if node then
            table.insert(results, node)
          end
        end
      end
    end
  end

  -- Sort by creation time
  table.sort(results, function(a, b)
    return a.ts.cr > b.ts.cr
  end)

  if limit and #results > limit then
    local limited = {}
    for i = 1, limit do
      limited[i] = results[i]
    end
    return limited
  end

  return results
end

--- Find semantically similar nodes
---@param query string Query text
---@param limit? number Max results
---@return Node[]
function M.semantic_search(query, limit)
  local result = M.execute({
    query = query,
    limit = limit or 10,
    depth = 2,
  })
  return result.nodes
end

--- Get context chain (path) for explanation
---@param node_ids string[] Node IDs to chain
---@return string[] Chain descriptions
function M.get_context_chain(node_ids)
  local node_mod = get_node_module()
  local edge_mod = get_edge_module()
  local chain = {}

  for i, node_id in ipairs(node_ids) do
    local node = node_mod.get(node_id)
    if node then
      local entry = string.format("[%s] %s (w:%.2f)", node.t:upper(), node.c.s, node.sc.w)
      table.insert(chain, entry)

      -- Add edge to next node if exists
      if node_ids[i + 1] then
        local edge = edge_mod.get(node_id, node_ids[i + 1])
        if edge then
          table.insert(chain, string.format("  -> %s (w:%.2f)", edge.ty, edge.p.w))
        end
      end
    end
  end

  return chain
end

return M
