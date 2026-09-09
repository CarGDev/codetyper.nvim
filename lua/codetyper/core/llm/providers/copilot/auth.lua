--- Copilot OAuth token discovery and GitHub token refresh
local M = {}

local http = require("codetyper.core.llm.shared.http")
local flog = require("codetyper.support.flog")

local AUTH_URL = "https://api.github.com/copilot_internal/v2/token"

--- Cached state (singleton per session)
M.state = nil

local valid_cache = nil
local valid_cache_time = 0
local quota_cache = nil
local quota_cache_time = 0

local function has_text(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function escape_pattern(value)
  return value:gsub("([^%w])", "%%%1")
end

local function redact(value)
  local text = tostring(value or "")
  local secrets = {}
  if M.state then
    secrets[#secrets + 1] = M.state.oauth_token
    if type(M.state.github_token) == "table" then
      secrets[#secrets + 1] = M.state.github_token.token
    end
  end
  for _, secret in ipairs(secrets) do
    if has_text(secret) then
      text = text:gsub(escape_pattern(secret), "[REDACTED]")
    end
  end
  if http.redact then
    text = http.redact(text)
  end
  return text
end

local function report_error(message)
  local safe_message = redact(message)
  flog.error("copilot.auth", safe_message)
  return safe_message
end

local function invalidate_model_cache()
  local models = package.loaded["codetyper.core.llm.providers.copilot.models"]
  if models and models.invalidate then
    models.invalidate()
  end
end

local function clear_cached_auth()
  valid_cache = nil
  valid_cache_time = 0
  quota_cache = nil
  quota_cache_time = 0
  if M.state then
    M.state.github_token = nil
  end
  invalidate_model_cache()
end

--- Validate an exchanged Copilot token before any downstream use.
---@param token table|nil
---@return boolean valid, string|nil error
function M.validate_exchange(token)
  if type(token) ~= "table" or not has_text(token.token) then
    return false, "Copilot authentication response did not contain a usable token"
  end
  if type(token.endpoints) ~= "table" or not has_text(token.endpoints.api) then
    return false, "Copilot authentication response did not contain a usable API endpoint"
  end
  return true, nil
end

M.redact = redact
M.safe_error = redact

--- Discover OAuth token from copilot.lua or copilot.vim config files
---@return string|nil OAuth token
function M.discover_oauth_token()
  local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
  local os_name = vim.loop.os_uname().sysname:lower()

  local config_dir
  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    config_dir = xdg_config
  elseif os_name:match("linux") or os_name:match("darwin") then
    config_dir = vim.fn.expand("~/.config")
  else
    config_dir = vim.fn.expand("~/AppData/Local")
  end

  local paths = { "hosts.json", "apps.json" }
  for _, filename in ipairs(paths) do
    local path = config_dir .. "/github-copilot/" .. filename
    if vim.fn.filereadable(path) == 1 then
      local content = vim.fn.readfile(path)
      if content and #content > 0 then
        local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
        if ok and data then
          for key, value in pairs(data) do
            if key:match("github.com") and value.oauth_token then
              return value.oauth_token
            end
          end
        end
      end
    end
  end

  return nil
end

--- Initialize state if needed
function M.ensure_initialized()
  if not M.state then
    M.state = {
      oauth_token = M.discover_oauth_token(),
      github_token = nil,
    }
  end
end

--- Refresh GitHub API token using OAuth token
---@param callback fun(token: table|nil, error: string|nil)
function M.refresh_github_token(callback)
  M.ensure_initialized()

  if not M.state or not has_text(M.state.oauth_token) then
    callback(nil, report_error("No OAuth token available"))
    return
  end

  -- Check if current token is still valid
  local cached_valid = M.validate_exchange(M.state.github_token)
  local expires_at = M.state.github_token and tonumber(M.state.github_token.expires_at)
  if cached_valid and expires_at and expires_at > os.time() then
    callback(M.state.github_token, nil)
    return
  elseif M.state.github_token then
    M.state.github_token = nil
  end

  local headers = {
    "Authorization: token " .. M.state.oauth_token,
    "Accept: application/json",
  }

  http.get(AUTH_URL, headers, function(parsed, err)
    if err then
      clear_cached_auth()
      callback(nil, report_error("Token refresh failed: " .. err))
      return
    end

    local github_message
    if type(parsed) == "table" then
      if type(parsed.message) == "string" then
        github_message = parsed.message
      elseif type(parsed.error_description) == "string" then
        github_message = parsed.error_description
      elseif type(parsed.error) == "string" then
        github_message = parsed.error
      elseif type(parsed.error) == "table" then
        github_message = parsed.error.message
      end
    end
    if github_message then
      clear_cached_auth()
      callback(nil, report_error("Copilot authentication failed: " .. github_message))
      return
    end

    local valid, validation_error = M.validate_exchange(parsed)
    if not valid then
      clear_cached_auth()
      callback(nil, report_error(validation_error))
      return
    end

    M.state.github_token = parsed
    callback(parsed, nil)
  end)
end

--- Get a valid GitHub token (refreshes if expired)
---@param callback fun(token: table|nil, error: string|nil)
function M.get_valid_token(callback)
  M.refresh_github_token(callback)
end

--- Check if a validated exchanged token is cached.
---@return boolean
function M.is_authenticated()
  M.ensure_initialized()
  return M.state ~= nil and M.validate_exchange(M.state.github_token)
end

--- Cached real-auth-validity result (short TTL to avoid hammering GitHub)
local VALID_CACHE_TTL = 60 -- seconds

--- Actually verify Copilot authentication by attempting a real token exchange.
--- This is the correct way to gate "should we use Copilot" decisions — unlike
--- is_authenticated() it confirms the token is still valid, not just present.
---@param callback fun(valid: boolean)
function M.is_valid(callback)
  if valid_cache ~= nil and (os.time() - valid_cache_time) < VALID_CACHE_TTL then
    callback(valid_cache)
    return
  end

  M.ensure_initialized()
  if not M.state or not has_text(M.state.oauth_token) then
    valid_cache = false
    valid_cache_time = os.time()
    callback(false)
    return
  end

  M.get_valid_token(function(_, err)
    local token_valid = err == nil and M.validate_exchange(M.state and M.state.github_token)
    if not token_valid then
      M.state.github_token = nil
      invalidate_model_cache()
    end
    valid_cache = token_valid
    valid_cache_time = os.time()
    callback(valid_cache)
  end)
end

--- Invalidate the cached auth-validity result (call after a known auth failure
--- so the next check re-verifies immediately instead of waiting out the TTL)
function M.invalidate_valid_cache()
  clear_cached_auth()
end

--- Cached quota snapshot
local QUOTA_CACHE_TTL = 300 -- 5 minutes

--- Fetch live Copilot account usage/quota (premium request credits) from
--- GitHub's copilot_internal/user endpoint.
---@param callback fun(quota: table|nil, error: string|nil)
function M.get_quota(callback)
  if quota_cache and (os.time() - quota_cache_time) < QUOTA_CACHE_TTL then
    callback(quota_cache, nil)
    return
  end

  M.ensure_initialized()
  if not M.state or not has_text(M.state.oauth_token) then
    callback(nil, "No OAuth token available")
    return
  end

  local headers = {
    "Authorization: token " .. M.state.oauth_token,
    "Accept: application/vnd.github+json",
  }

  http.get("https://api.github.com/copilot_internal/user", headers, function(parsed, err)
    if err then
      quota_cache = nil
      callback(nil, "Quota fetch failed: " .. redact(err))
      return
    end

    if not parsed or parsed.message == "Not Found" then
      quota_cache = nil
      callback(nil, "Quota data unavailable")
      return
    end

    local snapshot = parsed.quota_snapshots and parsed.quota_snapshots.premium_interactions
    local quota = {
      credits_used = snapshot and snapshot.credits_used or 0,
      entitlement = snapshot and snapshot.entitlement or 0,
      remaining = snapshot and snapshot.remaining or 0,
      percent_remaining = snapshot and snapshot.percent_remaining or 100,
      unlimited = snapshot and snapshot.unlimited or false,
      reset_date = parsed.quota_reset_date,
    }

    quota_cache = quota
    quota_cache_time = os.time()
    callback(quota, nil)
  end)
end

return M
