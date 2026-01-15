--- Brain Storage Layer
--- Cache + disk persistence with lazy loading

local utils = require("codetyper.utils")
local types = require("codetyper.brain.types")

local M = {}

--- In-memory cache keyed by project root
---@type table<string, table>
local cache = {}

--- Dirty flags for pending writes
---@type table<string, table<string, boolean>>
local dirty = {}

--- Debounce timers
---@type table<string, userdata>
local timers = {}

local DEBOUNCE_MS = 500

--- Get brain directory path for current project
---@param root? string Project root (defaults to current)
---@return string Brain directory path
function M.get_brain_dir(root)
  root = root or utils.get_project_root()
  return root .. "/.coder/brain"
end

--- Ensure brain directory structure exists
---@param root? string Project root
---@return boolean Success
function M.ensure_dirs(root)
  local brain_dir = M.get_brain_dir(root)
  local dirs = {
    brain_dir,
    brain_dir .. "/nodes",
    brain_dir .. "/indices",
    brain_dir .. "/deltas",
    brain_dir .. "/deltas/objects",
  }
  for _, dir in ipairs(dirs) do
    if not utils.ensure_dir(dir) then
      return false
    end
  end
  return true
end

--- Get file path for a storage key
---@param key string Storage key (e.g., "meta", "nodes.patterns", "deltas.objects.abc123")
---@param root? string Project root
---@return string File path
function M.get_path(key, root)
  local brain_dir = M.get_brain_dir(root)
  local parts = vim.split(key, ".", { plain = true })

  if #parts == 1 then
    return brain_dir .. "/" .. key .. ".json"
  elseif #parts == 2 then
    return brain_dir .. "/" .. parts[1] .. "/" .. parts[2] .. ".json"
  else
    return brain_dir .. "/" .. table.concat(parts, "/") .. ".json"
  end
end

--- Get cache for project
---@param root? string Project root
---@return table Project cache
local function get_cache(root)
  root = root or utils.get_project_root()
  if not cache[root] then
    cache[root] = {}
    dirty[root] = {}
  end
  return cache[root]
end

--- Read JSON from disk
---@param filepath string File path
---@return table|nil Data or nil on error
local function read_json(filepath)
  local content = utils.read_file(filepath)
  if not content or content == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end
  return data
end

--- Write JSON to disk
---@param filepath string File path
---@param data table Data to write
---@return boolean Success
local function write_json(filepath, data)
  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    return false
  end
  return utils.write_file(filepath, json)
end

--- Load data from disk into cache
---@param key string Storage key
---@param root? string Project root
---@return table|nil Data or nil
function M.load(key, root)
  root = root or utils.get_project_root()
  local project_cache = get_cache(root)

  -- Return cached if available
  if project_cache[key] ~= nil then
    return project_cache[key]
  end

  -- Load from disk
  local filepath = M.get_path(key, root)
  local data = read_json(filepath)

  -- Cache the result (even nil to avoid repeated reads)
  project_cache[key] = data or {}

  return project_cache[key]
end

--- Save data to cache and schedule disk write
---@param key string Storage key
---@param data table Data to save
---@param root? string Project root
---@param immediate? boolean Skip debounce
function M.save(key, data, root, immediate)
  root = root or utils.get_project_root()
  local project_cache = get_cache(root)

  -- Update cache
  project_cache[key] = data
  dirty[root][key] = true

  if immediate then
    M.flush(key, root)
    return
  end

  -- Debounced write
  local timer_key = root .. ":" .. key
  if timers[timer_key] then
    timers[timer_key]:stop()
  end

  timers[timer_key] = vim.defer_fn(function()
    M.flush(key, root)
    timers[timer_key] = nil
  end, DEBOUNCE_MS)
end

--- Flush a key to disk immediately
---@param key string Storage key
---@param root? string Project root
---@return boolean Success
function M.flush(key, root)
  root = root or utils.get_project_root()
  local project_cache = get_cache(root)

  if not dirty[root][key] then
    return true
  end

  M.ensure_dirs(root)
  local filepath = M.get_path(key, root)
  local data = project_cache[key]

  if data == nil then
    -- Delete file if data is nil
    os.remove(filepath)
    dirty[root][key] = nil
    return true
  end

  local success = write_json(filepath, data)
  if success then
    dirty[root][key] = nil
  end
  return success
end

--- Flush all dirty keys to disk
---@param root? string Project root
function M.flush_all(root)
  root = root or utils.get_project_root()
  if not dirty[root] then
    return
  end

  for key, is_dirty in pairs(dirty[root]) do
    if is_dirty then
      M.flush(key, root)
    end
  end
end

--- Get meta.json data
---@param root? string Project root
---@return GraphMeta
function M.get_meta(root)
  local meta = M.load("meta", root)
  if not meta or not meta.v then
    meta = {
      v = types.SCHEMA_VERSION,
      head = nil,
      nc = 0,
      ec = 0,
      dc = 0,
    }
    M.save("meta", meta, root)
  end
  return meta
end

--- Update meta.json
---@param updates table Partial updates
---@param root? string Project root
function M.update_meta(updates, root)
  local meta = M.get_meta(root)
  for k, v in pairs(updates) do
    meta[k] = v
  end
  M.save("meta", meta, root)
end

--- Get nodes by type
---@param node_type string Node type (e.g., "patterns", "corrections")
---@param root? string Project root
---@return table<string, Node> Nodes indexed by ID
function M.get_nodes(node_type, root)
  return M.load("nodes." .. node_type, root) or {}
end

--- Save nodes by type
---@param node_type string Node type
---@param nodes table<string, Node> Nodes indexed by ID
---@param root? string Project root
function M.save_nodes(node_type, nodes, root)
  M.save("nodes." .. node_type, nodes, root)
end

--- Get graph adjacency
---@param root? string Project root
---@return Graph Graph data
function M.get_graph(root)
  local graph = M.load("graph", root)
  if not graph or not graph.adj then
    graph = {
      adj = {},
      radj = {},
    }
    M.save("graph", graph, root)
  end
  return graph
end

--- Save graph
---@param graph Graph Graph data
---@param root? string Project root
function M.save_graph(graph, root)
  M.save("graph", graph, root)
end

--- Get index by type
---@param index_type string Index type (e.g., "by_file", "by_time")
---@param root? string Project root
---@return table Index data
function M.get_index(index_type, root)
  return M.load("indices." .. index_type, root) or {}
end

--- Save index
---@param index_type string Index type
---@param data table Index data
---@param root? string Project root
function M.save_index(index_type, data, root)
  M.save("indices." .. index_type, data, root)
end

--- Get delta by hash
---@param hash string Delta hash
---@param root? string Project root
---@return Delta|nil Delta data
function M.get_delta(hash, root)
  return M.load("deltas.objects." .. hash, root)
end

--- Save delta
---@param delta Delta Delta data
---@param root? string Project root
function M.save_delta(delta, root)
  M.save("deltas.objects." .. delta.h, delta, root, true) -- Immediate write for deltas
end

--- Get HEAD delta hash
---@param root? string Project root
---@return string|nil HEAD hash
function M.get_head(root)
  local meta = M.get_meta(root)
  return meta.head
end

--- Set HEAD delta hash
---@param hash string|nil Delta hash
---@param root? string Project root
function M.set_head(hash, root)
  M.update_meta({ head = hash }, root)
end

--- Clear all caches (for testing)
function M.clear_cache()
  cache = {}
  dirty = {}
  for _, timer in pairs(timers) do
    if timer then
      timer:stop()
    end
  end
  timers = {}
end

--- Check if brain exists for project
---@param root? string Project root
---@return boolean
function M.exists(root)
  local brain_dir = M.get_brain_dir(root)
  return vim.fn.isdirectory(brain_dir) == 1
end

return M
