--- Central provider resolver — single source of truth for Copilot vs Ollama.
---
--- Rule: Copilot is always tried first. Ollama is used ONLY as a fallback
--- when Copilot authentication is unavailable/invalid. This replaces the
--- previously uncoordinated logic scattered across selector/select.lua,
--- scheduler.lua (get_primary_provider/get_remote_provider), and the
--- rate-limit auto-switch in providers/copilot/init.lua.
local M = {}

local auth = require("codetyper.core.llm.providers.copilot.auth")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Cached resolution (short TTL so hot paths aren't blocked on network checks)
local resolved_cache = nil
local resolved_cache_time = 0
local RESOLVE_CACHE_TTL = 30 -- seconds

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
--- Copilot-first: only falls back to Ollama when Copilot auth is invalid.
---@param callback fun(provider: string|nil, err: string|nil)
function M.resolve(callback)
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
--- Uses the cached result if fresh; otherwise falls back to config default
--- and kicks off a background async resolve to warm the cache for next time.
---@return string provider
function M.resolve_sync()
  if resolved_cache and (os.time() - resolved_cache_time) < RESOLVE_CACHE_TTL then
    return resolved_cache
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
  return "copilot"
end

--- Invalidate the resolver cache (e.g. after a Copilot request fails)
function M.invalidate()
  resolved_cache = nil
  resolved_cache_time = 0
  auth.invalidate_valid_cache()
end

return M
