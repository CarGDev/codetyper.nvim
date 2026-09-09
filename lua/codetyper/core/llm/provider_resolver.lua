--- Central provider resolver — single source of truth for provider selection.
---
--- Rule: an explicit provider is never replaced. Without an explicit choice,
--- Copilot is tried first and Ollama is used only when Copilot authentication
--- is unavailable/invalid. This keeps selector, scheduler, and the LLM facade
--- on the same routing policy.
local M = {}

local auth = require("codetyper.core.llm.providers.copilot.auth")
local flog = require("codetyper.support.flog")

local SUPPORTED_PROVIDERS = {
  ollama = true,
  copilot = true,
  claude = true,
  openai = true,
}

--- Cached resolution (short TTL so hot paths aren't blocked on network checks)
local resolved_cache = nil
local resolved_cache_time = 0
local RESOLVE_CACHE_TTL = 30 -- seconds

---@param provider string|nil
---@return boolean
function M.is_supported(provider)
  return type(provider) == "string" and SUPPORTED_PROVIDERS[provider] == true
end

---@param provider string|nil
---@return boolean, string|nil
function M.validate_provider(provider)
  if M.is_supported(provider) then
    return true, nil
  end
  return false, "Unsupported LLM provider: " .. tostring(provider)
end

--- Find an active provider explicitly selected by the user.
--- The default Copilot configuration is intentionally not treated as an
--- explicit choice, so it can still participate in Copilot-first fallback.
---@return string|nil
function M.get_explicit_provider()
  local ok_credentials, credentials = pcall(require, "codetyper.config.credentials")
  if ok_credentials and credentials.get_active_provider then
    local active = credentials.get_active_provider()
    if M.is_supported(active) then
      return active
    end
  end

  local ok_codetyper, codetyper = pcall(require, "codetyper")
  if not ok_codetyper or not codetyper.get_config then
    return nil
  end

  local config = codetyper.get_config()
  local provider = config and config.llm and config.llm.provider
  if provider and provider ~= "copilot" and M.is_supported(provider) then
    return provider
  end
  return nil
end

--- Check if Ollama is configured (host set)
---@return boolean
local function is_ollama_configured()
  local ok, codetyper = pcall(require, "codetyper")
  if not ok then
    return false
  end
  local config = codetyper.get_config()
  return config and config.llm and config.llm.ollama and config.llm.ollama.host ~= nil
end

--- Quick reachability check for Ollama (short timeout, non-blocking)
---@param callback fun(reachable: boolean)
local function check_ollama_reachable(callback)
  local ok, codetyper = pcall(require, "codetyper")
  local host = "http://localhost:11434"
  if ok then
    local config = codetyper.get_config()
    if config and config.llm and config.llm.ollama and config.llm.ollama.host then
      host = config.llm.ollama.host
    end
  end

  local done = false
  vim.fn.jobstart({ "curl", "-s", "-m", "2", "-o", "/dev/null", "-w", "%{http_code}", host .. "/api/tags" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if done then return end
      if data and data[1] and data[1]:match("^200") then
        done = true
        callback(true)
      end
    end,
    on_exit = function(_, code)
      if done then return end
      done = true
      callback(code == 0)
    end,
  })
end

--- Resolve which provider should be used right now.
---@param callback fun(provider: string|nil, err: string|nil)
---@param explicit_provider string|nil Provider selected by the user
function M.resolve(callback, explicit_provider)
  -- Accept resolve(provider, callback) for callers that put the choice first.
  if type(callback) == "string" and type(explicit_provider) == "function" then
    callback, explicit_provider = explicit_provider, callback
  end

  explicit_provider = explicit_provider or M.get_explicit_provider()
  if explicit_provider then
    local valid, validation_error = M.validate_provider(explicit_provider)
    if not valid then
      callback(nil, validation_error)
      return
    end
    callback(explicit_provider, nil)
    return
  end

  if resolved_cache and (os.time() - resolved_cache_time) < RESOLVE_CACHE_TTL then
    callback(resolved_cache, nil)
    return
  end

  auth.is_valid(function(copilot_ok)
    if copilot_ok then
      resolved_cache = "copilot"
      resolved_cache_time = os.time()
      callback("copilot", nil)
      return
    end

    flog.info("provider_resolver", "Copilot auth invalid/unavailable, checking Ollama fallback")

    if not is_ollama_configured() then
      callback(nil, "Copilot not authenticated and Ollama is not configured. Run :Coder auth or configure llm.ollama.host.")
      return
    end

    check_ollama_reachable(function(reachable)
      if not reachable then
        callback(nil, "Copilot not authenticated and Ollama is unreachable. Start Ollama with: ollama serve")
        return
      end
      resolved_cache = "ollama"
      resolved_cache_time = os.time()
      callback("ollama", nil)
    end)
  end)
end

--- Synchronous best-effort resolution for call sites that can't go async.
--- Uses the cached result if fresh; otherwise falls back to the automatic
--- policy and kicks off a background async resolve to warm the cache.
---@param explicit_provider string|nil Provider selected by the user
---@return string|nil provider
---@return string|nil error
function M.resolve_sync(explicit_provider)
  explicit_provider = explicit_provider or M.get_explicit_provider()
  if explicit_provider then
    local valid, validation_error = M.validate_provider(explicit_provider)
    if not valid then
      return nil, validation_error
    end
    return explicit_provider, nil
  end

  if resolved_cache and (os.time() - resolved_cache_time) < RESOLVE_CACHE_TTL then
    return resolved_cache, nil
  end

  -- Warm the cache in the background for the next call
  M.resolve(function() end)

  -- Best-effort default while we don't have a fresh async result yet:
  -- prefer copilot unless we know it's already been invalidated.
  local ok, codetyper = pcall(require, "codetyper")
  if ok then
    local config = codetyper.get_config()
    if config and config.llm and config.llm.provider then
      return config.llm.provider
    end
  end
  return "copilot", nil
end

--- Invalidate the resolver cache (e.g. after a Copilot request fails)
function M.invalidate()
  resolved_cache = nil
  resolved_cache_time = 0
  auth.invalidate_valid_cache()
end

return M
