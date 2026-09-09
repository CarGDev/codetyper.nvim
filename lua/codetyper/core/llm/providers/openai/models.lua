--- Versioned ChatGPT subscription model policy.
---
--- ChatGPT OAuth does not use a public /models endpoint here. The allowlist
--- and filter mirror the verified OpenCode Codex plugin evidence instead of
--- guessing from ordinary OpenAI API-key catalogs.
local M = {}

M.PROVIDER = "openai"
M.LABEL = "OpenAI (ChatGPT Plus/Pro)"
M.ALLOWLIST_VERSION = "opencode-codex-allowlist-v1"
M.ALLOWLIST_SOURCE = "OpenCode codex.ts"

local ALLOWED_MODELS = {
  ["gpt-5.5"] = true,
  ["gpt-5.3-codex-spark"] = true,
  ["gpt-5.4"] = true,
  ["gpt-5.4-mini"] = true,
}

local DISALLOWED_MODELS = {
  ["gpt-5.5-pro"] = true,
  ["gpt-5.6"] = true,
}

local VERIFIED_RECORDS = {
  { id = "gpt-5.3-codex-spark", name = "GPT-5.3 Codex Spark" },
  { id = "gpt-5.4", name = "GPT-5.4" },
  { id = "gpt-5.4-mini", name = "GPT-5.4 Mini" },
  { id = "gpt-5.5", name = "GPT-5.5" },
}

local function model_id(item)
  if type(item) ~= "table" then
    return nil
  end
  if type(item.id) == "string" then
    return item.id
  end
  if type(item.api) == "table" and type(item.api.id) == "string" then
    return item.api.id
  end
  return nil
end

local function is_subscription_record(item)
  if type(item) ~= "table" then
    return false
  end
  if item.subscription == false or item.auth_type == "api" or item.api_key == true then
    return false
  end
  if item.provider and item.provider ~= "openai" then
    return false
  end
  return true
end

local function is_verified_model(id, item)
  if not id or DISALLOWED_MODELS[id] or not is_subscription_record(item) then
    return false
  end
  local options = type(item.options) == "table" and item.options or {}
  if options.reasoningMode == "pro" or options.reasoning_mode == "pro" then
    return false
  end
  if ALLOWED_MODELS[id] then
    return true
  end
  local major, minor = id:match("^gpt%-(%d+)%.(%d+)")
  if not major then
    major = id:match("^gpt%-(%d+)")
  end
  major, minor = tonumber(major), tonumber(minor or 0)
  -- Match the verified OpenCode filter while retaining explicit denials above.
  return major ~= nil and (major > 5 or major == 5 and minor > 4)
end

local function descriptor(item, id)
  local capabilities = type(item.capabilities) == "table" and vim.deepcopy(item.capabilities) or {}
  capabilities.streaming = false
  capabilities.tools = false
  return {
    id = id,
    name = item.name or item.display_name or id,
    provider = M.PROVIDER,
    subscription = true,
    catalog_version = M.ALLOWLIST_VERSION,
    cost = 0,
    capabilities = capabilities,
  }
end

--- Filter provider records using only the verified subscription policy.
---@param records table[]
---@return table[]|nil models, string|nil error
function M.filter(records)
  if type(records) ~= "table" then
    return nil, "OpenAI subscription catalog is unstable"
  end
  local result = {}
  for _, item in ipairs(records) do
    local id = model_id(item)
    if is_verified_model(id, item) then
      result[#result + 1] = descriptor(item, id)
    end
  end
  table.sort(result, function(left, right)
    return left.id < right.id
  end)
  return result, nil
end

--- Return the exact model metadata currently verified by OpenCode evidence.
---@return table[]
function M.known_models()
  return vim.deepcopy(VERIFIED_RECORDS)
end

--- Load a static verified catalog or caller-supplied verified records.
---@param callback fun(models: table[]|nil, error: string|nil, metadata: table|nil)
---@param options table|nil
---@return table handle
function M.fetch(callback, options)
  options = options or {}
  callback = callback or function() end
  local cancelled = false
  local metadata = {
    catalog_version = M.ALLOWLIST_VERSION,
    source = M.ALLOWLIST_SOURCE,
  }
  local handle = {}
  function handle.cancel()
    cancelled = true
  end

  if options.expected_version and options.expected_version ~= M.ALLOWLIST_VERSION then
    metadata.state = "unstable"
    callback(nil, "OpenAI subscription catalog is unstable", metadata)
    return handle
  end

  local records = options.records == nil and M.known_models() or options.records
  if type(records) ~= "table" then
    metadata.state = "unstable"
    callback(nil, "OpenAI subscription catalog is unstable", metadata)
    return handle
  end
  local models, filter_error = M.filter(records)
  if cancelled then
    return handle
  end
  if filter_error then
    metadata.state = "unstable"
    callback(nil, filter_error, metadata)
    return handle
  end
  local malformed = 0
  for _, item in ipairs(records) do
    local id = model_id(item)
    if is_subscription_record(item) and (not id or not is_verified_model(id, item)) then
      malformed = malformed + 1
    end
  end
  metadata.state = #models == 0 and "empty" or (malformed > 0 and "partial" or "ready")
  callback(models, nil, metadata)
  return handle
end

---@param options table|nil
---@return fun(callback: function): table
function M.source(options)
  return function(callback)
    return M.fetch(callback, options)
  end
end

M.allowed_models = vim.deepcopy(ALLOWED_MODELS)
M.disallowed_models = vim.deepcopy(DISALLOWED_MODELS)

return M
