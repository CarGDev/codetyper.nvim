local MODULES = {
  "codetyper.core.llm.providers.copilot.auth",
  "codetyper.core.llm.providers.copilot.models",
  "codetyper.core.llm.providers.copilot.request",
  "codetyper.core.llm.providers.copilot.init",
}

local INJECTED_MODULES = {
  "codetyper.core.llm.shared.http",
  "codetyper.support.flog",
  "codetyper.support.utils",
  "codetyper",
}

local function stub_http()
  local requests = {}
  local http = {}

  local function add_request(kind, url, headers, body, callback, options)
    local request = {
      kind = kind,
      url = url,
      headers = headers,
      body = body,
      callback = callback,
      options = options,
      cancelled = false,
    }
    function request.cancel()
      request.cancelled = true
    end
    requests[#requests + 1] = request
    return request
  end

  function http.get(url, headers, callback)
    return add_request("get", url, headers, nil, callback)
  end

  function http.post(url, headers, body, callback)
    return add_request("post", url, headers, body, callback)
  end

  function http.post_stream(url, headers, body, options)
    return add_request("post_stream", url, headers, body, nil, options)
  end

  return http, requests
end

local function load_copilot(http)
  package.loaded["codetyper.core.llm.shared.http"] = http
  for _, module_name in ipairs(MODULES) do
    package.loaded[module_name] = nil
  end

  local ok, modules = pcall(function()
    return {
      auth = require("codetyper.core.llm.providers.copilot.auth"),
      models = require("codetyper.core.llm.providers.copilot.models"),
      request = require("codetyper.core.llm.providers.copilot.request"),
      client = require("codetyper.core.llm.providers.copilot"),
    }
  end)
  assert.is_true(ok, modules)
  return modules
end

describe("Copilot authentication safety", function()
  local original_modules

  before_each(function()
    original_modules = {}
    for _, module_name in ipairs(INJECTED_MODULES) do
      original_modules[module_name] = package.loaded[module_name]
    end
    package.loaded["codetyper.support.flog"] = {
      info = function() end,
      warn = function() end,
      error = function() end,
      debug = function() end,
    }
    package.loaded["codetyper.support.utils"] = {
      notify = function() end,
    }
    package.loaded["codetyper"] = {
      get_config = function()
        return { llm = { copilot = { model = "gpt-4o" } } }
      end,
    }
  end)

  after_each(function()
    for _, module_name in ipairs(MODULES) do
      package.loaded[module_name] = nil
    end
    for _, module_name in ipairs(INJECTED_MODULES) do
      package.loaded[module_name] = original_modules[module_name]
    end
  end)

  it("surfaces GitHub message errors and invalidates malformed exchanges", function()
    local http, requests = stub_http()
    local modules = load_copilot(http)
    modules.auth.state = { oauth_token = "unit-oauth-secret", github_token = nil }
    local token, request_error

    modules.auth.refresh_github_token(function(result, err)
      token, request_error = result, err
    end)
    assert.are.equal("get", requests[1].kind)
    requests[1].callback({ message = "Bad credentials" }, nil)

    assert.is_nil(token)
    assert.matches("Bad credentials", request_error)
    assert.is_nil(modules.auth.state.github_token)
  end)

  it("rejects empty token and endpoint fields before downstream use", function()
    local http, requests = stub_http()
    local modules = load_copilot(http)
    local responses = {
      { token = "", endpoints = { api = "https://exchange.example" } },
      { token = "unit-access-secret", endpoints = {} },
    }

    for _, response in ipairs(responses) do
      modules.auth.state = { oauth_token = "unit-oauth-secret", github_token = nil }
      local token, request_error
      modules.auth.refresh_github_token(function(result, err)
        token, request_error = result, err
      end)
      requests[#requests].callback(response, nil)
      assert.is_nil(token)
      assert.matches("Copilot", request_error)
      assert.is_nil(modules.auth.state.github_token)
    end
  end)

  it("invalidates validity and token caches so a known failure is rechecked", function()
    local http, requests = stub_http()
    local modules = load_copilot(http)
    modules.auth.state = { oauth_token = "unit-oauth-secret", github_token = nil }
    local first_valid

    modules.auth.is_valid(function(valid)
      first_valid = valid
    end)
    requests[1].callback({
      token = "unit-access-secret",
      expires_at = os.time() + 3600,
      endpoints = { api = "https://exchange.example" },
    }, nil)
    assert.is_true(first_valid)

    modules.auth.invalidate_valid_cache()
    local second_valid
    modules.auth.is_valid(function(valid)
      second_valid = valid
    end)
    assert.are.equal(2, #requests)
    requests[2].callback({ message = "expired exchange" }, nil)

    assert.is_false(second_valid)
    assert.is_nil(modules.auth.state.github_token)
  end)

  it("returns safe auth errors for nil-token models and requests", function()
    local http, requests = stub_http()
    local modules = load_copilot(http)
    modules.auth.get_valid_token = function(callback)
      callback(nil, nil)
    end

    local fetched, fetch_error
    modules.models.fetch(function(result, err)
      fetched, fetch_error = result, err
    end)
    assert.is_nil(fetched)
    assert.matches("authentication", fetch_error:lower())
    assert.are.equal(0, #requests)

    local headers, header_error = modules.request.build_headers(nil)
    assert.is_nil(headers)
    assert.matches("authentication", header_error:lower())

    local response, request_error
    modules.request.send(nil, { model = "gpt-4o" }, function(result, err)
      response, request_error = result, err
    end)
    assert.is_nil(response)
    assert.matches("authentication", request_error:lower())
    assert.are.equal(0, #requests)

    local stream_error
    local job_id = modules.request.send_stream(nil, { model = "gpt-4o", stream = true }, {
      on_chunk = function() end,
      on_done = function() end,
      on_error = function(err)
        stream_error = err
      end,
    })
    assert.are.equal(-1, job_id)
    assert.matches("authentication", stream_error:lower())
    assert.are.equal(0, #requests)
  end)

  it("uses only the exchange-supplied endpoint after a valid exchange", function()
    local http, requests = stub_http()
    local modules = load_copilot(http)
    modules.auth.state = { oauth_token = "unit-oauth-secret", github_token = nil }
    local fetched, fetch_error

    modules.models.fetch(function(result, err)
      fetched, fetch_error = result, err
    end)
    requests[1].callback({
      token = "unit-access-secret",
      endpoints = { api = "https://exchange.example/internal" },
      expires_at = os.time() + 3600,
    }, nil)
    assert.are.equal("https://exchange.example/internal/models", requests[2].url)
    assert.are.equal("Authorization: Bearer unit-access-secret", requests[2].headers[1])

    requests[2].callback({
      data = {
        {
          id = "gpt-4o",
          name = "GPT-4o",
          capabilities = { type = "chat", supports = { streaming = true } },
          model_picker_enabled = true,
        },
      },
    }, nil)
    assert.is_nil(fetch_error)
    assert.are.equal("gpt-4o", fetched[1].id)
    assert.are.equal("gpt-4o", modules.models.find("gpt-4o").id)
    modules.auth.invalidate_valid_cache()
    assert.is_nil(modules.models.find("gpt-4o"))
  end)

  it("redacts OAuth and exchange secrets from diagnostics", function()
    local http, requests = stub_http()
    local messages = {}
    package.loaded["codetyper.support.flog"] = {
      info = function(_, message)
        messages[#messages + 1] = message
      end,
      warn = function(_, message)
        messages[#messages + 1] = message
      end,
      error = function(_, message)
        messages[#messages + 1] = message
      end,
      debug = function(_, message)
        messages[#messages + 1] = message
      end,
    }
    local modules = load_copilot(http)
    modules.auth.state = { oauth_token = "unit-oauth-secret", github_token = nil }
    local request_error

    modules.auth.refresh_github_token(function(_, err)
      request_error = err
    end)
    requests[1].callback({ message = "token unit-oauth-secret rejected" }, nil)

    assert.is_false(request_error:find("unit-oauth-secret", 1, true) ~= nil)
    assert.is_true(#messages > 0, "expected captured Copilot diagnostics")
    for _, message in ipairs(messages) do
      assert.is_false(message:find("unit-oauth-secret", 1, true) ~= nil)
      assert.is_false(message:find("unit-access-secret", 1, true) ~= nil)
    end
  end)

  it("rejects one malformed exchange before recovering through the same catalog path", function()
    local http, requests = stub_http()
    local modules = load_copilot(http)
    modules.models.save_to_disk = function() end
    modules.auth.state = { oauth_token = "unit-oauth-token", github_token = nil }

    local first_models, first_error
    modules.models.fetch(function(result, err)
      first_models, first_error = result, err
    end)
    assert.are.equal(1, #requests)
    requests[1].callback({ message = "expired exchange" }, nil)

    assert.is_nil(first_models)
    assert.matches("expired exchange", first_error)
    assert.is_nil(modules.auth.state.github_token)
    assert.is_false(modules.auth.is_authenticated())
    assert.is_nil(modules.models.find("gpt-4o"))

    local recovered_models, recovery_error
    modules.models.fetch(function(result, err)
      recovered_models, recovery_error = result, err
    end)
    assert.are.equal(2, #requests)
    requests[2].callback({
      token = "unit-access-token",
      expires_at = os.time() + 3600,
      endpoints = { api = "https://exchange.example" },
    }, nil)

    assert.are.equal(3, #requests)
    assert.are.equal("https://exchange.example/models", requests[3].url)
    requests[3].callback({
      data = {
        {
          id = "gpt-4o",
          name = "GPT-4o",
          capabilities = { type = "chat", supports = { streaming = true } },
          model_picker_enabled = true,
        },
      },
    }, nil)

    assert.is_nil(recovery_error)
    assert.are.equal(1, #recovered_models)
    assert.are.equal("gpt-4o", recovered_models[1].id)
    assert.are.equal("unit-access-token", modules.auth.state.github_token.token)
    assert.is_true(modules.auth.is_authenticated())
    assert.same(recovered_models[1], modules.models.find("gpt-4o"))
  end)
end)
