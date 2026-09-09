--- Headless ChatGPT device authorization with bounded, cancellable polling.
local oauth = require("codetyper.core.llm.providers.openai.oauth")
local shared_http = require("codetyper.core.llm.shared.http")

local M = {}

local DEVICE_CODE_PATH = "/api/accounts/deviceauth/usercode"
local DEVICE_TOKEN_PATH = "/api/accounts/deviceauth/token"
local DEVICE_URL_PATH = "/codex/device"
local POLLING_SAFETY_MARGIN = 3000
local DEFAULT_TIMEOUT = 600

local function has_text(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function default_transport()
  local transport = {}
  function transport.post(url, headers, body, callback)
    local ok, encoded = pcall(vim.json.encode, body)
    if not ok then
      callback(nil, "OpenAI device authorization request could not be encoded")
      return { cancel = function() end }
    end
    return shared_http.post(url, headers, encoded, callback)
  end
  return transport
end

local function status_of(payload, metadata)
  return tonumber(metadata and metadata.status) or tonumber(payload and payload.status) or 0
end

local function response_error(payload)
  if type(payload) ~= "table" then
    return nil
  end
  if type(payload.error) == "string" then
    return payload.error
  end
  if type(payload.error) == "table" and type(payload.error.code) == "string" then
    return payload.error.code
  end
  return type(payload.message) == "string" and payload.message or nil
end

local function safe_error(value)
  return oauth.redact(value or "OpenAI device authorization failed")
end

--- Begin device authorization and return a cancellable flow handle.
---@param options table|nil
---@param callback fun(tokens: table|nil, error: string|nil)
---@return table handle
function M.start(options, callback)
  options = options or {}
  callback = callback or function() end
  local transport = options.transport or default_transport()
  local schedule = options.schedule or vim.defer_fn
  local now = options.now or os.time
  local issuer = options.issuer or oauth.ISSUER
  local interval = math.max(tonumber(options.interval) or 5, 1) * 1000
  local deadline = now() + (tonumber(options.timeout) or DEFAULT_TIMEOUT)
  local cancelled, finished = false, false
  local current_request, timer
  local device_data
  local handle = {}

  local function cancel_handle(value)
    if value and value.cancel then
      value.cancel()
    elseif type(value) == "number" then
      pcall(vim.fn.timer_stop, value)
    end
  end

  local function stop_pending()
    cancel_handle(current_request)
    cancel_handle(timer)
    current_request, timer = nil, nil
  end

  local function finish(tokens, err)
    if finished or cancelled then
      return
    end
    finished = true
    stop_pending()
    callback(tokens, err and safe_error(err) or nil)
  end

  local function schedule_poll(callback_fn)
    if finished or cancelled then
      return
    end
    cancel_handle(timer)
    timer = schedule(callback_fn, interval + POLLING_SAFETY_MARGIN)
  end

  local function exchange_device_code(authorization_code, code_verifier)
    if not has_text(authorization_code) or not has_text(code_verifier) then
      finish(nil, "OpenAI device authorization response is malformed")
      return
    end
    local exchange = options.exchange
      or function(code, redirect_uri, pkce, done)
        return oauth.exchange_code(code, redirect_uri, pkce, done, {
          issuer = issuer,
          transport = transport,
        })
      end
    current_request =
      exchange(authorization_code, issuer .. "/deviceauth/callback", { verifier = code_verifier }, finish)
  end

  local poll
  poll = function()
    if finished or cancelled then
      return
    end
    if now() >= deadline then
      finish(nil, "OpenAI device authorization expired")
      return
    end

    current_request = transport.post(issuer .. DEVICE_TOKEN_PATH, {
      "Content-Type: application/json",
      "User-Agent: codetyper.nvim",
    }, {
      device_auth_id = device_data.device_auth_id,
      user_code = device_data.user_code,
    }, function(payload, err, metadata)
      if finished or cancelled then
        return
      end
      current_request = nil
      local status = status_of(payload, metadata)
      local error_code = response_error(payload)
      if err then
        finish(nil, err)
        return
      end
      if error_code == "authorization_pending" or status == 403 or status == 404 then
        schedule_poll(poll)
        return
      end
      if error_code == "slow_down" or status == 429 then
        interval = interval + 5000
        schedule_poll(poll)
        return
      end
      if error_code == "expired_token" or error_code == "expired" or status == 410 then
        finish(nil, "OpenAI device authorization expired")
        return
      end
      if error_code == "access_denied" or error_code == "authorization_denied" or status == 400 or status == 401 then
        finish(nil, "OpenAI device authorization denied")
        return
      end
      if status >= 400 then
        finish(nil, "OpenAI device authorization is unavailable")
        return
      end
      if type(payload) ~= "table" then
        finish(nil, "OpenAI device authorization response is malformed")
        return
      end
      exchange_device_code(payload.authorization_code, payload.code_verifier)
    end)
  end

  local initial_request = transport.post(issuer .. DEVICE_CODE_PATH, {
    "Content-Type: application/json",
    "User-Agent: codetyper.nvim",
  }, { client_id = oauth.CLIENT_ID }, function(payload, err, metadata)
    if finished or cancelled then
      return
    end
    current_request = nil
    local status = status_of(payload, metadata)
    if err then
      finish(nil, err)
      return
    end
    if status >= 400 then
      finish(nil, "OpenAI device authorization is unavailable")
      return
    end
    if type(payload) ~= "table" or not has_text(payload.device_auth_id) or not has_text(payload.user_code) then
      finish(nil, "OpenAI device authorization response is malformed")
      return
    end
    device_data = payload
    interval = math.max(tonumber(payload.interval) or 5, 1) * 1000
    if options.on_ready then
      options.on_ready({
        url = issuer .. DEVICE_URL_PATH,
        user_code = payload.user_code,
        interval = interval,
      })
    end
    if options.open_browser then
      options.open_browser(issuer .. DEVICE_URL_PATH)
    end
    schedule_poll(poll)
  end)
  current_request = initial_request

  function handle.cancel()
    if finished or cancelled then
      return
    end
    cancelled, finished = true, true
    stop_pending()
  end

  handle.poll = poll
  return handle
end

M.device_code_path = DEVICE_CODE_PATH
M.device_token_path = DEVICE_TOKEN_PATH
M.polling_safety_margin = POLLING_SAFETY_MARGIN

return M
