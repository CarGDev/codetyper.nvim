--- Brain Output Formatter
--- LLM-optimized output formatting

local types = require("codetyper.brain.types")

local M = {}

--- Estimate token count (rough approximation)
---@param text string Text to estimate
---@return number Estimated tokens
function M.estimate_tokens(text)
  if not text then
    return 0
  end
  -- Rough estimate: 1 token ~= 4 characters
  return math.ceil(#text / 4)
end

--- Format nodes to compact text format
---@param result QueryResult Query result
---@param opts? table Options
---@return string Formatted output
function M.to_compact(result, opts)
  opts = opts or {}
  local max_tokens = opts.max_tokens or 4000
  local lines = {}
  local current_tokens = 0

  -- Header
  table.insert(lines, "---BRAIN_CONTEXT---")
  if opts.query then
    table.insert(lines, "Q: " .. opts.query)
  end
  table.insert(lines, "")

  -- Add nodes by relevance (already sorted)
  table.insert(lines, "Learnings:")

  for i, node in ipairs(result.nodes) do
    -- Format: [idx] TYPE | w:0.85 u:5 | Summary
    local line = string.format(
      "[%d] %s | w:%.2f u:%d | %s",
      i,
      (node.t or "?"):upper(),
      node.sc.w or 0,
      node.sc.u or 0,
      (node.c.s or ""):sub(1, 100)
    )

    local line_tokens = M.estimate_tokens(line)
    if current_tokens + line_tokens > max_tokens - 100 then
      table.insert(lines, "... (truncated)")
      break
    end

    table.insert(lines, line)
    current_tokens = current_tokens + line_tokens

    -- Add context if file-related
    if node.ctx and node.ctx.f then
      local ctx_line = "   @ " .. node.ctx.f
      if node.ctx.fn then
        ctx_line = ctx_line .. ":" .. node.ctx.fn
      end
      if node.ctx.ln then
        ctx_line = ctx_line .. " L" .. node.ctx.ln[1]
      end
      table.insert(lines, ctx_line)
      current_tokens = current_tokens + M.estimate_tokens(ctx_line)
    end
  end

  -- Add connections if space allows
  if #result.edges > 0 and current_tokens < max_tokens - 200 then
    table.insert(lines, "")
    table.insert(lines, "Connections:")

    for _, edge in ipairs(result.edges) do
      if current_tokens >= max_tokens - 50 then
        break
      end

      local conn_line = string.format(
        "  %s --%s(%.2f)--> %s",
        edge.s:sub(-8),
        edge.ty,
        edge.p.w or 0.5,
        edge.t:sub(-8)
      )
      table.insert(lines, conn_line)
      current_tokens = current_tokens + M.estimate_tokens(conn_line)
    end
  end

  table.insert(lines, "---END_CONTEXT---")

  return table.concat(lines, "\n")
end

--- Format nodes to JSON format
---@param result QueryResult Query result
---@param opts? table Options
---@return string JSON output
function M.to_json(result, opts)
  opts = opts or {}
  local max_tokens = opts.max_tokens or 4000

  local output = {
    _s = "brain-v1", -- Schema
    q = opts.query,
    l = {}, -- Learnings
    c = {}, -- Connections
  }

  local current_tokens = 50 -- Base overhead

  -- Add nodes
  for _, node in ipairs(result.nodes) do
    local entry = {
      t = node.t,
      s = (node.c.s or ""):sub(1, 150),
      w = node.sc.w,
      u = node.sc.u,
    }

    if node.ctx and node.ctx.f then
      entry.f = node.ctx.f
    end

    local entry_tokens = M.estimate_tokens(vim.json.encode(entry))
    if current_tokens + entry_tokens > max_tokens - 100 then
      break
    end

    table.insert(output.l, entry)
    current_tokens = current_tokens + entry_tokens
  end

  -- Add edges if space
  if current_tokens < max_tokens - 200 then
    for _, edge in ipairs(result.edges) do
      if current_tokens >= max_tokens - 50 then
        break
      end

      local e = {
        s = edge.s:sub(-8),
        t = edge.t:sub(-8),
        r = edge.ty,
        w = edge.p.w,
      }

      table.insert(output.c, e)
      current_tokens = current_tokens + 30
    end
  end

  return vim.json.encode(output)
end

--- Format as natural language
---@param result QueryResult Query result
---@param opts? table Options
---@return string Natural language output
function M.to_natural(result, opts)
  opts = opts or {}
  local max_tokens = opts.max_tokens or 4000
  local lines = {}
  local current_tokens = 0

  if #result.nodes == 0 then
    return "No relevant learnings found."
  end

  table.insert(lines, "Based on previous learnings:")
  table.insert(lines, "")

  -- Group by type
  local by_type = {}
  for _, node in ipairs(result.nodes) do
    by_type[node.t] = by_type[node.t] or {}
    table.insert(by_type[node.t], node)
  end

  local type_names = {
    [types.NODE_TYPES.PATTERN] = "Code Patterns",
    [types.NODE_TYPES.CORRECTION] = "Previous Corrections",
    [types.NODE_TYPES.CONVENTION] = "Project Conventions",
    [types.NODE_TYPES.DECISION] = "Architectural Decisions",
    [types.NODE_TYPES.FEEDBACK] = "User Preferences",
    [types.NODE_TYPES.SESSION] = "Session Context",
  }

  for node_type, nodes in pairs(by_type) do
    local type_name = type_names[node_type] or node_type

    table.insert(lines, "**" .. type_name .. "**")

    for _, node in ipairs(nodes) do
      if current_tokens >= max_tokens - 100 then
        table.insert(lines, "...")
        goto done
      end

      local bullet = string.format("- %s (confidence: %.0f%%)", node.c.s or "?", (node.sc.w or 0) * 100)

      table.insert(lines, bullet)
      current_tokens = current_tokens + M.estimate_tokens(bullet)

      -- Add detail if high weight
      if node.sc.w > 0.7 and node.c.d and #node.c.d > #(node.c.s or "") then
        local detail = "  " .. node.c.d:sub(1, 150)
        if #node.c.d > 150 then
          detail = detail .. "..."
        end
        table.insert(lines, detail)
        current_tokens = current_tokens + M.estimate_tokens(detail)
      end
    end

    table.insert(lines, "")
  end

  ::done::

  return table.concat(lines, "\n")
end

--- Format context chain for explanation
---@param chain table[] Chain of nodes and edges
---@return string Chain explanation
function M.format_chain(chain)
  local lines = {}

  for i, item in ipairs(chain) do
    if item.node then
      local prefix = i == 1 and "" or "  -> "
      table.insert(lines, string.format("%s[%s] %s (w:%.2f)", prefix, item.node.t:upper(), item.node.c.s:sub(1, 50), item.node.sc.w))
    end
    if item.edge then
      table.insert(lines, string.format("     via %s (w:%.2f)", item.edge.ty, item.edge.p.w))
    end
  end

  return table.concat(lines, "\n")
end

--- Compress output to fit token budget
---@param text string Text to compress
---@param max_tokens number Token budget
---@return string Compressed text
function M.compress(text, max_tokens)
  local current = M.estimate_tokens(text)

  if current <= max_tokens then
    return text
  end

  -- Simple truncation with ellipsis
  local ratio = max_tokens / current
  local target_chars = math.floor(#text * ratio * 0.9) -- 10% buffer

  return text:sub(1, target_chars) .. "\n...(truncated)"
end

--- Get minimal context for quick lookups
---@param nodes Node[] Nodes to format
---@return string Minimal context
function M.minimal(nodes)
  local items = {}

  for _, node in ipairs(nodes) do
    table.insert(items, string.format("%s:%s", node.t, (node.c.s or ""):sub(1, 40)))
  end

  return table.concat(items, " | ")
end

return M
