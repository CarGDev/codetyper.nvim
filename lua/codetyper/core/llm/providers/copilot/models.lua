--- Fetch available models from Copilot API and auto-detect capabilities
local auth = require("codetyper.core.llm.providers.copilot.auth")
local http = require("codetyper.core.llm.shared.http")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Cached models (refreshed once per session)
local models_cache = nil
local cache_time = 0
local CACHE_TTL = 3600 -- 1 hour

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
      callback(nil, err)
      return
    end

    local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com") .. "/models"

    local headers = {
      "Authorization: Bearer " .. token.token,
      "Accept: application/json",
      "User-Agent: GitHubCopilotChat/0.26.7",
      "Editor-Version: vscode/1.105.1",
      "Editor-Plugin-Version: copilot-chat/0.26.7",
      "Copilot-Integration-Id: vscode-chat",
    }

    http.get(endpoint, headers, function(parsed, http_err)
      if http_err then
        flog.warn("copilot.models", "fetch failed: " .. http_err) -- TODO: remove after debugging
        callback(nil, http_err)
        return
      end

      if not parsed or not parsed.data then
        callback(nil, "Invalid models response")
        return
      end

      -- Filter to chat-capable models only
      local models = {}
      for _, model in ipairs(parsed.data) do
        local caps = model.capabilities or {}
        if caps.type == "chat" then
          local supports = caps.supports or {}
          local limits = caps.limits or {}
          table.insert(models, {
            id = model.id,
            name = model.name or model.id,
            version = model.version,
            is_tool_capable = supports.tool_calls == true,
            max_input_tokens = limits.max_prompt_tokens,
            max_output_tokens = limits.max_output_tokens,
            supports_streaming = supports.streaming == true,
            enabled = model.policy and model.policy.state == "enabled",
            picker_enabled = model.model_picker_enabled,
          })
        end
      end

      flog.info("copilot.models", string.format("fetched %d chat models", #models)) -- TODO: remove after debugging

      models_cache = models
      cache_time = os.time()

      -- Save to disk for offline reference
      M.save_to_disk(models)

      callback(models, nil)
    end)
  end)
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

--- Save fetched models to .codetyper/models_cache.json
---@param models table[]
function M.save_to_disk(models)
  pcall(function()
    local utils = require("codetyper.support.utils")
    local root = utils.get_project_root()
    local cache_path = root .. "/.codetyper/models_cache.json"

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
    local utils = require("codetyper.support.utils")
    local root = utils.get_project_root()
    local cache_path = root .. "/.codetyper/models_cache.json"

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

--- Get models (cache → disk → API)
---@param callback fun(models: table[]|nil, error: string|nil)
function M.get(callback)
  if models_cache then
    callback(models_cache, nil)
    return
  end

  -- Try disk cache first
  local disk_models = M.load_from_disk()
  if disk_models then
    models_cache = disk_models
    callback(disk_models, nil)
    -- Refresh in background
    M.fetch(function() end)
    return
  end

  -- Fetch from API
  M.fetch(callback)
end

--- Invalidate cache
function M.invalidate()
  models_cache = nil
  cache_time = 0
end

return M
