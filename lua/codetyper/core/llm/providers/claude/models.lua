--- Anthropic model discovery adapter.
local http = require("codetyper.core.llm.shared.http")

local M = {}

local API_BASE = "https://api.anthropic.com"
local API_VERSION = "2023-06-01"

local function api_key()
  local value = vim.env.ANTHROPIC_API_KEY
  if type(value) ~= "string" or not value:match("%S") then
    return nil
  end
  return value
end

local function copy_capabilities(value)
  local capabilities = type(value) == "table" and vim.deepcopy(value) or {}
  -- This adapter intentionally exposes only the non-streaming, no-tools slice.
  capabilities.streaming = false
  capabilities.tools = false
  return capabilities
end

local function normalize_item(item)
  if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then
    return nil
  end

  return {
    id = item.id,
    name = item.display_name or item.name or item.id,
    provider = "claude",
    capabilities = copy_capabilities(item.capabilities),
  }
end

--- Return the environment-only Anthropic key.
---@return string|nil
function M.get_api_key()
  return api_key()
end

--- Return the exact headers required by the Anthropic models endpoint.
---@param key string
---@return string[]
function M.discovery_headers(key)
  return {
    "x-api-key: " .. key,
    "anthropic-version: " .. API_VERSION,
  }
end

--- Normalize Anthropic's /v1/models payload to catalog descriptors.
---@param payload table|nil
---@return table[]|nil models, string|nil error
function M.normalize(payload)
  if type(payload) ~= "table" or type(payload.data) ~= "table" then
    return nil, "Anthropic models response is malformed"
  end

  local result = {}
  for _, item in ipairs(payload.data) do
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

--- Fetch Anthropic models using only ANTHROPIC_API_KEY from the environment.
---@param callback fun(models: table[]|nil, error: string|nil, metadata: table|nil)
---@param options table|nil { base_url: string }
---@return table|nil handle
function M.fetch(callback, options)
  if type(callback) ~= "function" then
    options, callback = callback or {}, function() end
  end
  options = options or {}
  local key = api_key()
  if not key then
    callback(nil, "Anthropic unavailable: ANTHROPIC_API_KEY is not set")
    return nil
  end

  local base_url = options.base_url or API_BASE
  base_url = base_url:gsub("/+$", "")
  return http.get(base_url .. "/v1/models", M.discovery_headers(key), function(payload, err, metadata)
    if err then
      callback(nil, err, metadata)
      return
    end
    local models, normalize_error = M.normalize(payload)
    if normalize_error then
      callback(nil, normalize_error, metadata)
      return
    end
    callback(models, nil, metadata)
  end)
end

--- Create a catalog-compatible source function.
---@param options table|nil
---@return fun(callback: function): table|nil
function M.source(options)
  return function(callback)
    return M.fetch(callback, options)
  end
end

function M.is_available()
  return api_key() ~= nil
end

M.api_version = API_VERSION
M.base_url = API_BASE

return M
