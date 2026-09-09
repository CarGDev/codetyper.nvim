--- Session-only ChatGPT subscription authentication.
local oauth = require("codetyper.core.llm.providers.openai.oauth")
local device_auth = require("codetyper.core.llm.providers.openai.device_auth")

local M = {}

local REFRESH_SKEW = 60
local session

local function safe_error(value, secrets)
  if oauth.redact then
    return oauth.redact(value, secrets)
  end
  return tostring(value or "OpenAI authentication failed")
end

local function copy(value)
  return type(value) == "table" and vim.deepcopy(value) or value
end

local function public_status()
  if not session then
    return { authenticated = false }
  end
  return {
    authenticated = true,
    expires_at = session.expires_at,
    has_residency = session.residency ~= nil,
  }
end

local function normalize(raw, previous, validator)
  validator = validator or oauth
  if not validator.normalize_tokens then
    return nil, "OpenAI authentication validator is unavailable"
  end
  return validator.normalize_tokens(raw, previous)
end

--- Return metadata only; tokens and account identity never leave session state.
---@return table
function M.session_status()
  return public_status()
end

--- Clear the in-memory subscription session.
function M.clear()
  session = nil
end

--- Redact an authentication error before it reaches diagnostics or UI.
---@param value any
---@return string
function M.redact(value)
  return safe_error(value, session)
end

M.safe_error = M.redact

--- Start browser PKCE or headless device authentication.
---@param mode "browser"|"device"
---@param callback fun(status: table|nil, error: string|nil)
---@param options table|nil
---@return table handle
function M.start(mode, callback, options)
  options = options or {}
  callback = callback or function() end
  local cancelled, finished = false, false
  local flow
  local selected_oauth = options.oauth or oauth
  local selected_device = options.device_auth or device_auth

  local function finish(raw, err)
    if finished or cancelled then
      return
    end
    finished = true
    if err then
      session = nil
      callback(nil, safe_error(err))
      return
    end
    local validated, validation_error = normalize(raw, nil, selected_oauth)
    if not validated then
      session = nil
      callback(nil, safe_error(validation_error))
      return
    end
    session = validated
    callback(public_status(), nil)
  end

  local handle = {}
  function handle.cancel()
    if finished or cancelled then
      return
    end
    cancelled, finished = true, true
    if flow and flow.cancel then
      flow.cancel()
    end
  end

  if mode == "browser" then
    flow = selected_oauth.start_browser(options, finish)
  elseif mode == "device" then
    flow = selected_device.start(options, finish)
  else
    finish(nil, "OpenAI authentication mode is unsupported")
  end
  return handle
end

--- Return validated private session state to the isolated request adapter.
---@param callback fun(session: table|nil, error: string|nil)
---@param options table|nil
---@return table handle
function M.get_valid(callback, options)
  options = options or {}
  callback = callback or function() end
  local cancelled, finished = false, false
  local refresh_handle
  local now = options.now or os.time
  local skew = tonumber(options.refresh_skew) or REFRESH_SKEW
  local handle = {}

  local function finish(value, err)
    if finished or cancelled then
      return
    end
    finished = true
    callback(value and copy(value) or nil, err and safe_error(err, value or session) or nil)
  end

  function handle.cancel()
    if finished or cancelled then
      return
    end
    cancelled, finished = true, true
    if refresh_handle and refresh_handle.cancel then
      refresh_handle.cancel()
    end
  end

  if not session then
    finish(nil, "OpenAI unavailable: ChatGPT subscription is not authenticated")
    return handle
  end

  if tonumber(session.expires_at) and session.expires_at > now() + skew then
    finish(session, nil)
    return handle
  end

  if type(session.refresh_token) ~= "string" or session.refresh_token == "" then
    session = nil
    finish(nil, "OpenAI authentication expired and cannot be refreshed")
    return handle
  end

  local refresh = options.refresh
    or function(refresh_token, done)
      return (options.oauth or oauth).refresh_access_token(refresh_token, done, options)
    end
  refresh_handle = refresh(session.refresh_token, function(raw, err)
    if finished or cancelled then
      return
    end
    if err then
      session = nil
      finish(nil, "OpenAI token refresh failed: " .. safe_error(err))
      return
    end
    local refreshed, validation_error = normalize(raw, session, options.oauth or oauth)
    if not refreshed then
      session = nil
      finish(nil, validation_error)
      return
    end
    session = refreshed
    finish(session, nil)
  end)
  return handle
end

--- Synchronous metadata check for routing and menus.
---@return boolean
function M.is_authenticated()
  return session ~= nil
    and tonumber(session.expires_at) ~= nil
    and session.expires_at > os.time()
    and session.account_id ~= nil
end

return M
