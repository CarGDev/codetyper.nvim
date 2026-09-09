--- ChatGPT subscription OAuth contracts and browser PKCE flow.
---
--- The endpoints in this module are provider-specific OpenCode evidence. They
--- are deliberately isolated so contract drift becomes an unavailable state
--- instead of changing the other providers.
local M = {}

M.CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
M.ISSUER = "https://auth.openai.com"
M.CODEX_API_ENDPOINT = "https://chatgpt.com/backend-api/codex/responses"
M.CALLBACK_PORT = 1455
M.CALLBACK_PATH = "/auth/callback"
M.ALLOWLIST_SOURCE = "OpenCode codex.ts"

local function has_text(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function url_encode(value)
  local text = tostring(value or "")
  return (
    text:gsub("[^%w%-_%.~]", function(character)
      return string.format("%%%02X", string.byte(character))
    end)
  )
end

local function base64_url_encode(value)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local output = {}
  for index = 1, #value, 3 do
    local first = string.byte(value, index) or 0
    local second = string.byte(value, index + 1) or 0
    local third = string.byte(value, index + 2) or 0
    local triple = first * 65536 + second * 256 + third
    output[#output + 1] = alphabet:sub(math.floor(triple / 262144) + 1, math.floor(triple / 262144) + 1)
    output[#output + 1] = alphabet:sub(math.floor(triple / 4096) % 64 + 1, math.floor(triple / 4096) % 64 + 1)
    output[#output + 1] = index + 1 <= #value
        and alphabet:sub(math.floor(triple / 64) % 64 + 1, math.floor(triple / 64) % 64 + 1)
      or "="
    output[#output + 1] = index + 2 <= #value and alphabet:sub(triple % 64 + 1, triple % 64 + 1) or "="
  end
  return table.concat(output):gsub("%+", "-"):gsub("/", "_"):gsub("=+$", "")
end

local function base64_url_decode(value)
  if type(value) ~= "string" then
    return nil
  end
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local normalized = value:gsub("-", "+"):gsub("_", "/")
  normalized = normalized .. string.rep("=", (4 - #normalized % 4) % 4)
  local output = {}
  for index = 1, #normalized, 4 do
    local a = alphabet:find(normalized:sub(index, index), 1, true)
    local b = alphabet:find(normalized:sub(index + 1, index + 1), 1, true)
    local c = alphabet:find(normalized:sub(index + 2, index + 2), 1, true)
    local d = alphabet:find(normalized:sub(index + 3, index + 3), 1, true)
    if not a or not b then
      return nil
    end
    a, b = a - 1, b - 1
    c, d = (c and c - 1 or 0), (d and d - 1 or 0)
    local triple = a * 262144 + b * 4096 + c * 64 + d
    output[#output + 1] = string.char(math.floor(triple / 65536) % 256)
    if normalized:sub(index + 2, index + 2) ~= "=" then
      output[#output + 1] = string.char(math.floor(triple / 256) % 256)
    end
    if normalized:sub(index + 3, index + 3) ~= "=" then
      output[#output + 1] = string.char(triple % 256)
    end
  end
  return table.concat(output)
end

local function random_text(length)
  local seed = table.concat({ tostring(os.time()), tostring(math.random()), tostring(vim.loop.hrtime()) }, ":")
  local digest = vim.fn.sha256(seed)
  local value = digest
  while #value < length do
    value = value .. vim.fn.sha256(value)
  end
  return value:sub(1, length)
end

--- Generate the S256 PKCE verifier and challenge pair.
---@return table { verifier: string, challenge: string }
function M.generate_pkce()
  local verifier = random_text(43)
  local digest = vim.fn.sha256(verifier)
  local bytes = {}
  for index = 1, #digest, 2 do
    bytes[#bytes + 1] = string.char(tonumber(digest:sub(index, index + 1), 16))
  end
  return { verifier = verifier, challenge = base64_url_encode(table.concat(bytes)) }
end

--- Parse an untrusted JWT payload without validating its signature.
---@param token string
---@return table|nil claims
function M.parse_jwt_claims(token)
  if type(token) ~= "string" then
    return nil
  end
  local payload = token:match("^[^.]+%.([^.]+)%.[^.]+$")
  local decoded = payload and base64_url_decode(payload)
  if not decoded then
    return nil
  end
  local ok, claims = pcall(vim.json.decode, decoded)
  return ok and type(claims) == "table" and claims or nil
end

---@param claims table
---@return string|nil
function M.extract_account_id_from_claims(claims)
  if type(claims) ~= "table" then
    return nil
  end
  local namespaced = claims["https://api.openai.com/auth"]
  return claims.chatgpt_account_id
    or type(namespaced) == "table" and namespaced.chatgpt_account_id
    or type(claims.organizations) == "table"
      and type(claims.organizations[1]) == "table"
      and claims.organizations[1].id
end

---@param tokens table
---@return string|nil
function M.extract_account_id(tokens)
  if type(tokens) ~= "table" then
    return nil
  end
  local candidates = {}
  if tokens.id_token then
    candidates[#candidates + 1] = tokens.id_token
  end
  if tokens.access_token or tokens.access then
    candidates[#candidates + 1] = tokens.access_token or tokens.access
  end
  for _, token in ipairs(candidates) do
    local claims = M.parse_jwt_claims(token)
    local account_id = M.extract_account_id_from_claims(claims)
    if has_text(account_id) then
      return account_id
    end
  end
  return has_text(tokens.account_id) and tokens.account_id or nil
end

---@param token string
---@return string|nil
function M.extract_residency(token)
  local claims = M.parse_jwt_claims(token)
  local namespaced = claims and claims["https://api.openai.com/auth"]
  local residency = claims and claims.chatgpt_compute_residency
    or type(namespaced) == "table" and namespaced.chatgpt_compute_residency
  if not has_text(residency) or residency == "no_constraint" then
    return nil
  end
  return residency
end

local function timestamp(value)
  local number = tonumber(value)
  if not number then
    return nil
  end
  if number > 100000000000 then
    return math.floor(number / 1000)
  end
  return math.floor(number)
end

--- Normalize only the private fields required by the session provider.
---@param raw table
---@param previous table|nil
---@return table|nil tokens, string|nil error
function M.normalize_tokens(raw, previous)
  if type(raw) ~= "table" then
    return nil, "OpenAI authentication response is malformed"
  end
  local access_token = raw.access_token or raw.access
  local refresh_token = raw.refresh_token or raw.refresh
  if not has_text(access_token) or not has_text(refresh_token) then
    return nil, "OpenAI authentication response did not contain usable tokens"
  end

  local expires_at = timestamp(raw.expires_at or raw.expires)
  if not expires_at and raw.expires_in then
    expires_at = os.time() + (tonumber(raw.expires_in) or 0)
  end
  if not expires_at then
    return nil, "OpenAI authentication response did not contain an expiry"
  end

  local account_id = M.extract_account_id(raw) or previous and previous.account_id
  local residency = M.extract_residency(raw.id_token or access_token) or previous and previous.residency
  if not has_text(account_id) then
    return nil, "OpenAI authentication response did not contain a ChatGPT account ID"
  end

  return {
    access_token = access_token,
    refresh_token = refresh_token,
    expires_at = expires_at,
    account_id = account_id,
    residency = residency,
  },
    nil
end

local function redact_with_secrets(value, secrets)
  local text = tostring(value or "")
  for _, secret in ipairs(secrets or {}) do
    if has_text(secret) then
      text = text:gsub((tostring(secret):gsub("([^%w])", "%%%1")), "[REDACTED]")
    end
  end
  text = text:gsub("([Aa]uthorization:%s*[Bb]earer%s+)[^%s]+", "%1[REDACTED]")
  text = text:gsub("([Cc]hat[Gg][Pp][Tt]%-[Aa]ccount%-[Ii][Dd]:%s*)[^%s]+", "%1[REDACTED]")
  text = text:gsub("([Cc]ode%s*[:=]%s*)[^%s]+", "%1[REDACTED]")
  text = text:gsub("https?://[^%s%]]+", "[REDACTED_URL]")
  return text
end

--- Redact provider credentials and unstable endpoint details from diagnostics.
---@param value any
---@param secrets table|string|nil
---@return string
function M.redact(value, secrets)
  if type(secrets) == "string" then
    secrets = { secrets }
  elseif type(secrets) == "table" and secrets.access_token then
    secrets = { secrets.access_token, secrets.refresh_token, secrets.account_id, secrets.residency }
  end
  return redact_with_secrets(value, secrets)
end

M.safe_error = M.redact

---@param redirect_uri string
---@param pkce table
---@param state string
---@return string
function M.build_authorize_url(redirect_uri, pkce, state)
  local params = {
    { "response_type", "code" },
    { "client_id", M.CLIENT_ID },
    { "redirect_uri", redirect_uri },
    { "scope", "openid profile email offline_access" },
    { "code_challenge", pkce.challenge },
    { "code_challenge_method", "S256" },
    { "id_token_add_organizations", "true" },
    { "codex_cli_simplified_flow", "true" },
    { "state", state },
    { "originator", "codetyper" },
  }
  local query = {}
  for _, pair in ipairs(params) do
    query[#query + 1] = url_encode(pair[1]) .. "=" .. url_encode(pair[2])
  end
  return M.ISSUER .. "/oauth/authorize?" .. table.concat(query, "&")
end

local function default_transport()
  local transport = {}
  function transport.post(url, headers, body, callback)
    local command = { "curl", "--silent", "--show-error", "--request", "POST" }
    for _, header in ipairs(headers or {}) do
      command[#command + 1], command[#command + 2] = "--header", header
    end
    command[#command + 1], command[#command + 2] = "--data", body
    command[#command + 1] = url

    local finished, cancelled, output, job_id = false, false, "", nil
    local handle = {}
    local function finish(result, err)
      if finished then
        return
      end
      finished = true
      if not cancelled then
        callback(result, err)
      end
    end
    function handle.cancel()
      if finished then
        return
      end
      cancelled = true
      if job_id and job_id > 0 then
        vim.fn.jobstop(job_id)
      end
      finished = true
    end
    job_id = vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          output = output .. table.concat(data, "\n")
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          finish(nil, "OpenAI OAuth request failed")
          return
        end
        local ok, parsed = pcall(vim.json.decode, output)
        if not ok or type(parsed) ~= "table" then
          finish(nil, "OpenAI OAuth response is malformed")
          return
        end
        finish(parsed, nil)
      end,
    })
    if not job_id or job_id <= 0 then
      finish(nil, "OpenAI OAuth request could not start")
    end
    return handle
  end
  return transport
end

local function form_body(values)
  local fields = {}
  for _, key in ipairs({ "grant_type", "code", "redirect_uri", "client_id", "code_verifier", "refresh_token" }) do
    if values[key] then
      fields[#fields + 1] = url_encode(key) .. "=" .. url_encode(values[key])
    end
  end
  return table.concat(fields, "&")
end

--- Exchange a browser or device authorization code for a token response.
---@param code string
---@param redirect_uri string
---@param pkce table
---@param callback fun(tokens: table|nil, error: string|nil)
---@param options table|nil
function M.exchange_code(code, redirect_uri, pkce, callback, options)
  options = options or {}
  if not has_text(code) or not has_text(redirect_uri) or type(pkce) ~= "table" then
    callback(nil, "OpenAI authorization code exchange is malformed")
    return nil
  end
  local transport = options.transport or default_transport()
  return transport.post(
    (options.issuer or M.ISSUER) .. "/oauth/token",
    { "Content-Type: application/x-www-form-urlencoded" },
    form_body({
      grant_type = "authorization_code",
      code = code,
      redirect_uri = redirect_uri,
      client_id = M.CLIENT_ID,
      code_verifier = pkce.verifier,
    }),
    function(parsed, err)
      if err then
        callback(nil, M.redact(err))
      else
        callback(parsed, nil)
      end
    end
  )
end

--- Refresh an expired ChatGPT access token.
---@param refresh_token string
---@param callback fun(tokens: table|nil, error: string|nil)
---@param options table|nil
function M.refresh_access_token(refresh_token, callback, options)
  options = options or {}
  if not has_text(refresh_token) then
    callback(nil, "OpenAI refresh token is unavailable")
    return nil
  end
  local transport = options.transport or default_transport()
  return transport.post(
    (options.issuer or M.ISSUER) .. "/oauth/token",
    { "Content-Type: application/x-www-form-urlencoded" },
    form_body({
      grant_type = "refresh_token",
      refresh_token = refresh_token,
      client_id = M.CLIENT_ID,
    }),
    function(parsed, err)
      if err then
        callback(nil, M.redact(err))
      else
        callback(parsed, nil)
      end
    end
  )
end

local function parse_query(path)
  local query = {}
  for key, value in path:gmatch("[?&]([^=&#]+)=([^&#]*)") do
    query[key] = value:gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end)
  end
  return query
end

local function loopback_server(port)
  local uv = vim.uv or vim.loop
  if not uv or not uv.new_tcp then
    return nil, "OpenAI browser authentication is unavailable in this Neovim runtime"
  end
  local tcp = uv.new_tcp()
  local server = {}
  function server:start(handler)
    local ok, bind_error = pcall(function()
      tcp:bind("127.0.0.1", port)
      tcp:listen(16, function(listen_error)
        if listen_error then
          handler({ error = "OpenAI callback server failed" })
          return
        end
        local client = uv.new_tcp()
        tcp:accept(client)
        client:read_start(function(read_error, data)
          if read_error or not data then
            client:close()
            return
          end
          local path = data:match("^GET%s+([^%s]+)")
          if not path then
            client:close()
            return
          end
          local respond = function(status, body)
            local response = "HTTP/1.1 "
              .. tostring(status or 200)
              .. "\r\n"
              .. "Content-Type: text/plain; charset=utf-8\r\n"
              .. "Content-Length: "
              .. #body
              .. "\r\n\r\n"
              .. body
            client:write(response, function()
              client:close()
            end)
          end
          handler(parse_query(path), respond)
        end)
      end)
    end)
    if not ok then
      return nil, bind_error
    end
    return true
  end
  function server:stop()
    if not tcp:is_closing() then
      tcp:close()
    end
  end
  return server
end

--- Start browser PKCE authorization with a one-time loopback callback.
---@param options table|nil
---@param callback fun(tokens: table|nil, error: string|nil)
---@return table handle
function M.start_browser(options, callback)
  options = options or {}
  local cancelled, finished, consumed = false, false, false
  local server = options.server
  local server_error
  if not server then
    server, server_error = loopback_server(options.port or M.CALLBACK_PORT)
  end
  local state = options.state or base64_url_encode(random_text(32))
  local pkce = options.pkce or M.generate_pkce()
  local redirect_uri = options.redirect_uri
    or ("http://127.0.0.1:" .. (options.port or M.CALLBACK_PORT) .. M.CALLBACK_PATH)
  local timer
  local exchange_handle

  local function stop()
    if timer and timer.cancel then
      timer.cancel()
    elseif type(timer) == "number" then
      pcall(vim.fn.timer_stop, timer)
    end
    if server and server.stop then
      server:stop()
    end
    if exchange_handle and exchange_handle.cancel then
      exchange_handle.cancel()
    end
  end

  local function finish(tokens, err)
    if finished or cancelled then
      return
    end
    finished = true
    stop()
    callback(tokens, err and M.redact(err) or nil)
  end

  local function on_callback(params, respond)
    if finished or cancelled or consumed then
      if respond then
        respond(409, "OpenAI authorization callback already consumed")
      end
      return
    end
    params = type(params) == "table" and params or {}
    if params.error then
      consumed = true
      if respond then
        respond(200, "OpenAI authorization was denied")
      end
      finish(nil, params.error_description or params.error)
      return
    end
    if params.state ~= state then
      consumed = true
      if respond then
        respond(400, "OpenAI authorization state was invalid")
      end
      finish(nil, "OpenAI authorization state mismatch")
      return
    end
    if not has_text(params.code) then
      consumed = true
      if respond then
        respond(400, "OpenAI authorization code was missing")
      end
      finish(nil, "OpenAI authorization code was missing")
      return
    end
    consumed = true
    if respond then
      respond(200, "OpenAI authorization completed")
    end
    local exchange = options.exchange
      or function(code, uri, codes, done)
        return M.exchange_code(code, uri, codes, done, options)
      end
    exchange_handle = exchange(params.code, redirect_uri, pkce, finish)
  end

  if server_error then
    finish(nil, server_error)
  elseif not server then
    finish(nil, "OpenAI browser callback server is unavailable")
  else
    local started, start_error = server:start(on_callback)
    if started ~= true then
      finish(nil, start_error or "OpenAI browser callback server could not start")
    else
      local url = M.build_authorize_url(redirect_uri, pkce, state)
      local open_browser = options.open_browser or (vim.ui and vim.ui.open)
      if not open_browser then
        finish(nil, "OpenAI browser authentication is unavailable")
      else
        local opened = open_browser(url)
        if opened == false then
          finish(nil, "OpenAI browser could not be opened")
        end
      end
      local schedule = options.schedule or vim.defer_fn
      if not finished and schedule then
        timer = schedule(function()
          finish(nil, "OpenAI browser authorization expired")
        end, options.timeout or 300000)
      end
    end
  end

  local handle = {}
  function handle.cancel()
    if finished or cancelled then
      return
    end
    cancelled = true
    finished = true
    stop()
  end
  handle.accept = on_callback
  return handle
end

return M
