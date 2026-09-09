--- Ollama model discovery adapter for the shared async catalog.
local http = require("codetyper.core.llm.shared.http")

local M = {}

local function copy_capabilities(value)
  return type(value) == "table" and vim.deepcopy(value) or {}
end

local function normalize_item(item)
  if type(item) ~= "table" then
    return nil
  end

  local id = item.id or item.name or item.model
  if type(id) ~= "string" or id == "" then
    return nil
  end

  return {
    id = id,
    name = item.name or item.model or id,
    provider = "ollama",
    capabilities = copy_capabilities(item.capabilities or item.details),
  }
end

--- Normalize Ollama's /api/tags payload to catalog descriptors.
---@param payload table|nil
---@return table[]
function M.normalize(payload)
  local source = payload and (payload.models or payload) or {}
  local result = {}
  if type(source) ~= "table" then
    return result
  end

  for _, item in ipairs(source) do
    local descriptor = normalize_item(item)
    if descriptor then
      result[#result + 1] = descriptor
    end
  end

  table.sort(result, function(left, right)
    return left.id < right.id
  end)
  return result
end

local function configured_host()
  local ok, config = pcall(require, "codetyper.core.llm.providers.ollama.config")
  if ok and config.get_host then
    return config.get_host()
  end
  return "http://localhost:11434"
end

--- Fetch and normalize Ollama models.
---@param host string|fun(models: table[]|nil, error: string|nil)|nil
---@param callback fun(models: table[]|nil, error: string|nil, metadata: table|nil)|nil
---@return table|nil handle
function M.fetch(host, callback)
  if type(host) == "function" then
    callback, host = host, nil
  end
  callback = callback or function() end
  host = host or configured_host()

  if type(host) ~= "string" or host == "" then
    callback(nil, "Ollama unavailable: host is not configured")
    return nil
  end

  host = host:gsub("/+$", "")
  return http.get(host .. "/api/tags", {}, function(payload, err, metadata)
    if err then
      callback(nil, err, metadata)
      return
    end
    if not payload then
      callback(nil, "Ollama returned an empty response", metadata)
      return
    end
    callback(M.normalize(payload), nil, metadata)
  end)
end

--- Create a catalog-compatible source function for a configured host.
---@param host string|nil
---@return fun(callback: function): table|nil
function M.source(host)
  return function(callback)
    return M.fetch(host, callback)
  end
end

return M
