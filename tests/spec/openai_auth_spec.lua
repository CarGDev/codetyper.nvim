local function browser_server()
  local server = { started = false, stopped = false }

  function server:start(handler)
    self.handler = handler
    self.started = true
    return true
  end

  function server:stop()
    self.stopped = true
  end

  return server
end

local function transport_stub()
  local requests = {}
  local transport = {}

  function transport.post(url, headers, body, callback)
    local request = {
      url = url,
      headers = headers,
      body = body,
      callback = callback,
      cancelled = false,
    }
    function request.cancel()
      request.cancelled = true
    end
    requests[#requests + 1] = request
    return request
  end

  return transport, requests
end

local function timer_stub()
  local timers = {}

  local function schedule(callback, delay)
    local timer = { callback = callback, delay = delay, cancelled = false }
    function timer.cancel()
      timer.cancelled = true
    end
    timers[#timers + 1] = timer
    return timer
  end

  return schedule, timers
end

describe("OpenAI ChatGPT subscription authentication", function()
  it("accepts one browser PKCE callback, validates state, and exchanges the code", function()
    local oauth = require("codetyper.core.llm.providers.openai.oauth")
    local server = browser_server()
    local opened_url, exchanged
    local result, result_error

    oauth.start_browser({
      server = server,
      state = "browser-state",
      pkce = { verifier = "pkce-verifier", challenge = "pkce-challenge" },
      open_browser = function(url)
        opened_url = url
      end,
      exchange = function(code, redirect_uri, pkce, callback)
        exchanged = { code = code, redirect_uri = redirect_uri, pkce = pkce }
        callback({
          access_token = "access-token",
          refresh_token = "refresh-token",
          expires_in = 3600,
        })
      end,
    }, function(tokens, err)
      result, result_error = tokens, err
    end)

    assert.is_true(server.started)
    assert.matches("auth.openai.com/oauth/authorize", opened_url)
    assert.matches("code_challenge=pkce%-challenge", opened_url)
    assert.matches("state=browser%-state", opened_url)

    server.handler({ code = "authorization-code", state = "browser-state" })

    assert.is_nil(result_error)
    assert.are.equal("access-token", result.access_token)
    assert.are.equal("authorization-code", exchanged.code)
    assert.are.equal("http://127.0.0.1:1455/auth/callback", exchanged.redirect_uri)
    assert.are.equal("pkce-verifier", exchanged.pkce.verifier)
    assert.is_true(server.stopped)
  end)

  it("rejects a mismatched state and never exchanges a replayed callback", function()
    local oauth = require("codetyper.core.llm.providers.openai.oauth")
    local server = browser_server()
    local exchange_count, callback_count = 0, 0
    local last_error

    oauth.start_browser({
      server = server,
      state = "expected-state",
      pkce = { verifier = "verifier", challenge = "challenge" },
      open_browser = function() end,
      exchange = function(_, _, _, callback)
        exchange_count = exchange_count + 1
        callback({ access_token = "access", refresh_token = "refresh", expires_in = 3600 })
      end,
    }, function(_, err)
      callback_count = callback_count + 1
      last_error = err
    end)

    server.handler({ code = "wrong-state-code", state = "wrong-state" })
    assert.matches("state", last_error:lower())
    assert.are.equal(0, exchange_count)

    server.handler({ code = "late-code", state = "expected-state" })
    assert.are.equal(0, exchange_count)
    assert.are.equal(1, callback_count)
  end)

  it("cancels the browser listener and suppresses late callback delivery", function()
    local oauth = require("codetyper.core.llm.providers.openai.oauth")
    local server = browser_server()
    local callback_count = 0
    local handle = oauth.start_browser({
      server = server,
      state = "cancel-state",
      pkce = { verifier = "verifier", challenge = "challenge" },
      open_browser = function() end,
      exchange = function(_, _, _, callback)
        callback({ access_token = "access", refresh_token = "refresh", expires_in = 3600 })
      end,
    }, function()
      callback_count = callback_count + 1
    end)

    handle.cancel()
    server.handler({ code = "late-code", state = "cancel-state" })

    assert.is_true(server.stopped)
    assert.are.equal(0, callback_count)
  end)

  it("polls device authorization through pending, slow-down, and denial states", function()
    local device = require("codetyper.core.llm.providers.openai.device_auth")
    local transport, requests = transport_stub()
    local schedule, timers = timer_stub()
    local result, result_error

    device.start({
      transport = transport,
      schedule = schedule,
      open_browser = function() end,
    }, function(tokens, err)
      result, result_error = tokens, err
    end)

    requests[1].callback({ device_auth_id = "device-id", user_code = "ABCD", interval = "1" }, nil, { status = 200 })
    assert.matches("auth.openai.com/api/accounts/deviceauth/usercode", requests[1].url)
    assert.is_not_nil(requests[1].body.client_id)
    assert.are.equal(1, #timers)

    timers[1].callback()
    requests[2].callback(nil, nil, { status = 403 })
    assert.are.equal(2, #timers)

    timers[2].callback()
    requests[3].callback({ error = "slow_down" }, nil, { status = 429 })
    assert.are.equal(3, #timers)
    assert.is_true(timers[3].delay > timers[2].delay)

    timers[3].callback()
    requests[4].callback({ error = "access_denied" }, nil, { status = 400 })

    assert.is_nil(result)
    assert.matches("denied", result_error:lower())
  end)

  it("expires a device flow at its deadline and cancels pending polling", function()
    local device = require("codetyper.core.llm.providers.openai.device_auth")
    local transport, requests = transport_stub()
    local schedule, timers = timer_stub()
    local now = 100
    local result_error, callback_count = nil, 0

    local handle = device.start({
      transport = transport,
      schedule = schedule,
      now = function()
        return now
      end,
      timeout = 5,
    }, function(_, err)
      callback_count = callback_count + 1
      result_error = err
    end)

    requests[1].callback({ device_auth_id = "device-id", user_code = "ABCD", interval = "1" }, nil, { status = 200 })
    now = 106
    timers[1].callback()

    assert.are.equal(1, callback_count)
    assert.matches("expired", result_error:lower())
    assert.are.equal(1, #requests)

    handle.cancel()
    assert.is_true(timers[1].cancelled)
  end)

  it("redacts access, refresh, account, residency, codes, and headers from safe errors", function()
    local oauth = require("codetyper.core.llm.providers.openai.oauth")
    local message = oauth.redact(
      "access-token refresh-token account-123 eu-west authorization code=one "
        .. "Authorization: Bearer access-token ChatGPT-Account-Id: account-123 "
        .. "https://auth.openai.com/oauth/token",
      { "access-token", "refresh-token", "account-123", "eu-west", "one" }
    )

    assert.is_false(message:find("access-token", 1, true) ~= nil)
    assert.is_false(message:find("refresh-token", 1, true) ~= nil)
    assert.is_false(message:find("account-123", 1, true) ~= nil)
    assert.is_false(message:find("eu-west", 1, true) ~= nil)
    assert.is_false(message:find("auth.openai.com", 1, true) ~= nil)
  end)
end)
