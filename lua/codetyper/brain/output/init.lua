--- Brain Output Coordinator
--- Manages LLM context generation

local formatter = require("codetyper.brain.output.formatter")

local M = {}

-- Re-export formatter
M.formatter = formatter

--- Default token budget
local DEFAULT_MAX_TOKENS = 4000

--- Generate context for LLM prompt
---@param opts? table Options
---@return string Context string
function M.generate(opts)
  opts = opts or {}

  local brain = require("codetyper.brain")
  if not brain.is_initialized() then
    return ""
  end

  -- Build query opts
  local query_opts = {
    query = opts.query,
    file = opts.file,
    types = opts.types,
    since = opts.since,
    limit = opts.limit or 30,
    depth = opts.depth or 2,
    max_tokens = opts.max_tokens or DEFAULT_MAX_TOKENS,
  }

  -- Execute query
  local result = brain.query(query_opts)

  if #result.nodes == 0 then
    return ""
  end

  -- Format based on style
  local format = opts.format or "compact"

  if format == "json" then
    return formatter.to_json(result, query_opts)
  elseif format == "natural" then
    return formatter.to_natural(result, query_opts)
  else
    return formatter.to_compact(result, query_opts)
  end
end

--- Generate context for a specific file
---@param filepath string File path
---@param opts? table Options
---@return string Context string
function M.for_file(filepath, opts)
  opts = opts or {}
  opts.file = filepath
  return M.generate(opts)
end

--- Generate context for current buffer
---@param opts? table Options
---@return string Context string
function M.for_current_buffer(opts)
  local filepath = vim.fn.expand("%:p")
  if filepath == "" then
    return ""
  end
  return M.for_file(filepath, opts)
end

--- Generate context for a query/prompt
---@param query string Query text
---@param opts? table Options
---@return string Context string
function M.for_query(query, opts)
  opts = opts or {}
  opts.query = query
  return M.generate(opts)
end

--- Get context for LLM system prompt
---@param opts? table Options
---@return string System context
function M.system_context(opts)
  opts = opts or {}
  opts.limit = opts.limit or 20
  opts.format = opts.format or "compact"

  local context = M.generate(opts)

  if context == "" then
    return ""
  end

  return [[
The following context contains learned patterns and conventions from this project:

]] .. context .. [[


Use this context to inform your responses, following established patterns and conventions.
]]
end

--- Get relevant context for code completion
---@param prefix string Code before cursor
---@param suffix string Code after cursor
---@param filepath string Current file
---@return string Context
function M.for_completion(prefix, suffix, filepath)
  -- Extract relevant terms from code
  local terms = {}

  -- Get function/class names
  for word in prefix:gmatch("[A-Z][a-zA-Z0-9]+") do
    table.insert(terms, word)
  end
  for word in prefix:gmatch("function%s+([a-zA-Z_][a-zA-Z0-9_]*)") do
    table.insert(terms, word)
  end

  local query = table.concat(terms, " ")

  return M.generate({
    query = query,
    file = filepath,
    limit = 15,
    max_tokens = 2000,
    format = "compact",
  })
end

--- Check if context is available
---@return boolean
function M.has_context()
  local brain = require("codetyper.brain")
  if not brain.is_initialized() then
    return false
  end

  local stats = brain.stats()
  return stats.node_count > 0
end

--- Get context stats
---@return table Stats
function M.stats()
  local brain = require("codetyper.brain")
  if not brain.is_initialized() then
    return { available = false }
  end

  local stats = brain.stats()
  return {
    available = true,
    node_count = stats.node_count,
    edge_count = stats.edge_count,
  }
end

return M
