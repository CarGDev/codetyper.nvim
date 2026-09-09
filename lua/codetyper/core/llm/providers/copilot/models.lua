--- Fetch available models from Copilot API and auto-detect capabilities
local auth = require("codetyper.core.llm.providers.copilot.auth")
local http = require("codetyper.core.llm.shared.http")
local model_constants = require("codetyper.constants.models")

local M = {}

--- Cached models (refreshed per TTL)
local models_cache = nil
local cache_time = 0
local CACHE_TTL = 300 -- 5 minutes (same as CLI)

local function safe_error(message)
  if auth.safe_error then
    return auth.safe_error(message)
  end
  return tostring(message or "Copilot authentication failed")
end

local function endpoint_for(token)
  local valid, validation_error = auth.validate_exchange(token)
  if not valid then
    return nil, validation_error
  end
  local endpoint = token.endpoints.api:gsub("/+$", "")
  return endpoint, nil
end

--- Fetch models from Copilot API
---@param callback fun(models: table[]|nil, error: string|nil)
function M.fetch(callback)
  -- Return cache if fresh
  if models_cache and (os.time() - cache_time) < CACHE_TTL then
    callback(models_cache, nil)
    return
  end

  auth.get_valid_token(function(token, err)
    if err then
      M.invalidate()
      callback(nil, safe_error(err))
      return
    end

    local endpoint, endpoint_error = endpoint_for(token)
    if endpoint_error then
      M.invalidate()
      callback(nil, endpoint_error)
      return
    end

    local headers = {
      "Authorization: Bearer " .. token.token,
      "Accept: application/json",
      "User-Agent: GitHubCopilotChat/0.30.0",
      "Editor-Version: vscode/1.100.0",
      "Editor-Plugin-Version: copilot-chat/0.30.0",
      "Copilot-Integration-Id: vscode-chat",
    }

    http.get(endpoint .. "/models", headers, function(parsed, http_err, response_meta)
      if http_err then
        if response_meta and response_meta.status == 401 then
          auth.invalidate_valid_cache()
        end
        callback(nil, safe_error(http_err), response_meta)
        return
      end

      if type(parsed) ~= "table" or type(parsed.data) ~= "table" then
        callback(nil, "Copilot models response is malformed", response_meta)
        return
      end

      -- Filter to chat-capable, picker-enabled models
      local models = {}
      for _, model in ipairs(parsed.data) do
        if type(model) == "table" then
          local caps = type(model.capabilities) == "table" and model.capabilities or {}
          local supports = type(caps.supports) == "table" and caps.supports or {}
          local limits = type(caps.limits) == "table" and caps.limits or {}
          local billing = type(model.billing) == "table" and model.billing or {}

          if type(model.id) == "string" and model.id ~= "" and caps.type == "chat" and model.model_picker_enabled then
            -- Resolve cost multiplier: API billing > hardcoded fallback > 1.0
            local cost = billing.multiplier
            if cost == nil then
              cost = model_constants.cost_multipliers[model.id] or 1.0
            end

            local is_unlimited = (billing.is_premium == false)
              or (cost == 0)
              or (model_constants.unlimited_models[model.id] == true)

            table.insert(models, {
              id = model.id,
              name = model.name or model.id,
              provider = "copilot",
              capabilities = vim.deepcopy(supports),
              version = model.version,
              is_tool_capable = supports.tool_calls == true,
              max_input_tokens = limits.max_prompt_tokens,
              max_output_tokens = limits.max_output_tokens,
              supports_streaming = supports.streaming == true,
              supports_vision = supports.vision == true,
              enabled = model.policy and model.policy.state == "enabled",
              picker_enabled = true,
              cost_multiplier = cost,
              is_unlimited = is_unlimited,
              is_premium = billing.is_premium or false,
            })
          end
        end
      end

      models_cache = models
      cache_time = os.time()

      -- Persist metadata only; the exchanged token never enters this cache.
      M.save_to_disk(models)

      callback(models, nil, response_meta)
    end)
  end)
end

--- Get context size for a model (API data > hardcoded > default)
---@param model_id string
---@return table { input: number, output: number }
function M.get_context_size(model_id)
  -- Check cached models first (most accurate from API)
  if models_cache then
    for _, m in ipairs(models_cache) do
      if m.id == model_id and m.max_input_tokens then
        return {
          input = m.max_input_tokens,
          output = m.max_output_tokens or model_constants.default_context_size.output,
        }
      end
    end
  end
  -- Fallback to hardcoded constants
  return model_constants.context_sizes[model_id] or model_constants.default_context_size
end

--- Determine tier from model capabilities (auto-detected from API)
---@param model_info table Model info from fetch()
---@return string "agent"|"chat"|"basic"
function M.detect_tier(model_info)
  if model_info.is_tool_capable then
    return "agent"
  end
  if model_info.max_input_tokens and model_info.max_input_tokens >= 32000 then
    return "chat"
  end
  return "basic"
end

--- Save fetched models to global cache
---@param models table[]
function M.save_to_disk(models)
  pcall(function()
    local data_dir = vim.fn.stdpath("data")
    local cache_path = data_dir .. "/codetyper/copilot_models_cache.json"

    local dir = vim.fn.fnamemodify(cache_path, ":h")
    vim.fn.mkdir(dir, "p")

    local data = {
      updated = os.time(),
      models = models,
    }
    local json = vim.json.encode(data)
    local f = io.open(cache_path, "w")
    if f then
      f:write(json)
      f:close()
    end
  end)
end

--- Load cached models from disk (fallback when API unavailable)
---@return table[]|nil
function M.load_from_disk()
  local ok, result = pcall(function()
    local data_dir = vim.fn.stdpath("data")
    local cache_path = data_dir .. "/codetyper/copilot_models_cache.json"

    if vim.fn.filereadable(cache_path) ~= 1 then
      return nil
    end

    local content = table.concat(vim.fn.readfile(cache_path), "\n")
    local data = vim.json.decode(content)
    if data and data.models then
      return data.models
    end
    return nil
  end)

  if ok then
    return result
  end
  return nil
end

--- Get models (cache → disk → API → fallback)
---@param callback fun(models: table[]|nil, error: string|nil)
function M.get(callback)
  M.fetch(callback)
end

--- Find a model by id from cache
---@param model_id string
---@return table|nil
function M.find(model_id)
  if not models_cache then
    return nil
  end
  for _, m in ipairs(models_cache) do
    if m.id == model_id then
      return m
    end
  end
  return nil
end

--- Invalidate cache
function M.invalidate()
  models_cache = nil
  cache_time = 0
end

return M
