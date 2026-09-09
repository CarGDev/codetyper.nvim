local function base64url(value)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local result = {}
  local bytes = { string.byte(value, 1, #value) }
  for index = 1, #bytes, 3 do
    local a = bytes[index] or 0
    local b = bytes[index + 1] or 0
    local c = bytes[index + 2] or 0
    local triple = a * 65536 + b * 256 + c
    result[#result + 1] = alphabet:sub(math.floor(triple / 262144) + 1, math.floor(triple / 262144) + 1)
    result[#result + 1] = alphabet:sub(math.floor(triple / 4096) % 64 + 1, math.floor(triple / 4096) % 64 + 1)
    result[#result + 1] = index + 1 <= #bytes
        and alphabet:sub(math.floor(triple / 64) % 64 + 1, math.floor(triple / 64) % 64 + 1)
      or "="
    result[#result + 1] = index + 2 <= #bytes and alphabet:sub(triple % 64 + 1, triple % 64 + 1) or "="
  end
  return table.concat(result):gsub("%+", "-"):gsub("/", "_"):gsub("=+$", "")
end

local function jwt(payload)
  return "header." .. base64url(vim.json.encode(payload)) .. ".signature"
end

local function clear_modules(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

local function request_stub()
  local requests = {}
  local http = {}

  function http.post(url, headers, body, callback)
    local request = { url = url, headers = headers, body = body, callback = callback, cancelled = false }
    function request.cancel()
      request.cancelled = true
    end
    requests[#requests + 1] = request
    return request
  end

  return http, requests
end

local function auth_stub()
  local token = {
    access_token = "access-secret",
    account_id = "account-id",
    residency = "eu-west",
  }
  local auth = {}
  function auth.get_valid(callback)
    callback(token, nil)
    return { cancel = function() end }
  end
  function auth.redact(value)
    return tostring(value or ""):gsub("access%-secret", "[REDACTED]"):gsub("account%-id", "[REDACTED]")
  end
  return auth, token
end

describe("OpenAI ChatGPT subscription provider", function()
  after_each(function()
    clear_modules({
      "codetyper.core.llm.providers.openai",
      "codetyper.core.llm.providers.openai.init",
      "codetyper.core.llm.providers.openai.auth",
      "codetyper.core.llm.providers.openai.oauth",
      "codetyper.core.llm.providers.openai.device_auth",
      "codetyper.core.llm.providers.openai.models",
      "codetyper.core.llm.providers.openai.request",
      "codetyper.core.llm.providers.openai.response",
      "codetyper.core.llm.shared.http",
    })
  end)

  it("extracts the account and residency claims used by ChatGPT subscription requests", function()
    local oauth = require("codetyper.core.llm.providers.openai.oauth")
    local access = jwt({
      chatgpt_account_id = "account-from-access",
      chatgpt_compute_residency = "eu-west",
    })
    local tokens = oauth.normalize_tokens({
      access_token = access,
      refresh_token = "refresh-secret",
      expires_in = 3600,
    })

    assert.are.equal("account-from-access", tokens.account_id)
    assert.are.equal("eu-west", tokens.residency)
    assert.is_true(tokens.expires_at > os.time())
    assert.are.equal("refresh-secret", tokens.refresh_token)
  end)

  it("keeps validated OAuth credentials in session state and refreshes near-expiry access", function()
    package.loaded["codetyper.core.llm.providers.openai.oauth"] = nil
    local validator = require("codetyper.core.llm.providers.openai.oauth")
    local oauth = {
      normalize_tokens = validator.normalize_tokens,
      start_browser = function(_, callback)
        callback({
          access_token = jwt({ chatgpt_account_id = "account-id" }),
          refresh_token = "refresh-secret",
          expires_at = 1,
        })
        return { cancel = function() end }
      end,
      refresh_access_token = function(refresh_token, callback)
        assert.are.equal("refresh-secret", refresh_token)
        callback({
          access_token = jwt({ chatgpt_account_id = "account-id" }),
          refresh_token = "new-refresh-secret",
          expires_in = 3600,
        })
      end,
    }
    package.loaded["codetyper.core.llm.providers.openai.oauth"] = oauth
    local auth = require("codetyper.core.llm.providers.openai.auth")
    local started, start_error
    auth.start("browser", function(session, err)
      started, start_error = session, err
    end)

    assert.is_nil(start_error)
    assert.is_true(started.authenticated)
    local status = auth.session_status()
    assert.is_true(status.authenticated)
    assert.is_false(vim.inspect(status):find("refresh-secret", 1, true) ~= nil)
    assert.is_false(vim.inspect(status):find("account-id", 1, true) ~= nil)

    local refreshed, refresh_error
    auth.get_valid(function(session, err)
      refreshed, refresh_error = session, err
    end)

    assert.is_nil(refresh_error)
    assert.are.equal("new-refresh-secret", refreshed.refresh_token)
    assert.is_true(refreshed.expires_at > os.time())
  end)

  it("returns unavailable auth for malformed subscription tokens and supports cancellation", function()
    local flow
    local oauth = {
      start_browser = function(_, callback)
        flow = callback
        return { cancel = function() end }
      end,
    }
    package.loaded["codetyper.core.llm.providers.openai.oauth"] = oauth
    local auth = require("codetyper.core.llm.providers.openai.auth")
    local callback_count, auth_error = 0, nil
    local handle = auth.start("browser", function(_, err)
      callback_count = callback_count + 1
      auth_error = err
    end)
    handle.cancel()
    flow({ access_token = "not-a-jwt", refresh_token = "refresh-secret", expires_in = 3600 })

    assert.are.equal(0, callback_count)
    assert.is_nil(auth.session_status().authenticated and true or nil)
    assert.is_nil(auth_error)
  end)

  it("filters only verified ChatGPT subscription models and marks zero-cost capabilities", function()
    local models = require("codetyper.core.llm.providers.openai.models")
    local result, result_error = models.filter({
      { id = "gpt-5.5", name = "GPT-5.5", options = {} },
      { id = "gpt-5.4", name = "GPT-5.4", options = {} },
      { id = "gpt-5.5-pro", name = "GPT-5.5 Pro", options = { reasoningMode = "pro" } },
      { id = "gpt-5.6", name = "GPT-5.6", options = {} },
      { id = "gpt-4o", name = "GPT-4o", subscription = false },
    })

    assert.is_nil(result_error)
    assert.same({ "gpt-5.4", "gpt-5.5" }, { result[1].id, result[2].id })
    assert.are.equal("openai", result[1].provider)
    assert.is_true(result[1].subscription)
    assert.are.equal(0, result[1].cost)
    assert.are.equal(models.ALLOWLIST_VERSION, result[1].catalog_version)
    assert.is_false(result[1].capabilities.streaming)
    assert.is_false(result[1].capabilities.tools)
  end)

  it(
    "reports an unstable catalog for an unknown allowlist version and a partial catalog for malformed entries",
    function()
      local models = require("codetyper.core.llm.providers.openai.models")
      local result, result_error, metadata

      models.fetch(function(items, err, state)
        result, result_error, metadata = items, err, state
      end, { records = { { id = "gpt-5.5" } }, expected_version = "unknown-version" })
      assert.is_nil(result)
      assert.matches("unstable", result_error:lower())
      assert.are.equal("unstable", metadata.state)

      models.fetch(function(items, err, state)
        result, result_error, metadata = items, err, state
      end, {
        records = { { id = "gpt-5.5" }, { id = "not-a-chatgpt-model" } },
        expected_version = models.ALLOWLIST_VERSION,
      })
      assert.is_nil(result_error)
      assert.are.equal(1, #result)
      assert.are.equal("partial", metadata.state)
      assert.are.equal("OpenCode codex.ts", metadata.source)
    end
  )

  it("builds the non-streaming Codex request with account and optional residency headers", function()
    local request = require("codetyper.core.llm.providers.openai.request")
    local body, body_error = request.build_body("gpt-5.5", "system", "prompt")
    assert.is_nil(body_error)
    assert.same({ model = "gpt-5.5", instructions = "system", input = "prompt", stream = false }, body)

    local streamed, stream_error = request.build_body("gpt-5.5", "", "prompt", { stream = true })
    assert.is_nil(streamed)
    assert.matches("streaming is not supported", stream_error)

    local tooled, tools_error = request.build_body("gpt-5.5", "", "prompt", { tools = { { name = "terminal" } } })
    assert.is_nil(tooled)
    assert.matches("tools are not supported", tools_error)
  end)

  it("sends and parses non-streaming Codex responses, errors, and cancellation without stale callbacks", function()
    local http, requests = request_stub()
    local auth = auth_stub()
    package.loaded["codetyper.core.llm.shared.http"] = http
    package.loaded["codetyper.core.llm.providers.openai.auth"] = auth
    local request = require("codetyper.core.llm.providers.openai.request")
    local response = require("codetyper.core.llm.providers.openai.response")
    local body = request.build_body("gpt-5.5", "system", "prompt")
    local generated, request_error, callback_count

    request.send(body, function(parsed, err)
      callback_count = (callback_count or 0) + 1
      generated, request_error = parsed, err
    end)
    assert.are.equal("https://chatgpt.com/backend-api/codex/responses", requests[1].url)
    assert.same({
      "Authorization: Bearer access-secret",
      "Content-Type: application/json",
      "ChatGPT-Account-Id: account-id",
      "x-openai-internal-codex-residency: eu-west",
    }, requests[1].headers)
    local encoded = vim.json.decode(requests[1].body)
    assert.is_false(encoded.stream)
    requests[1].callback({
      output = { { type = "message", content = { { type = "output_text", text = "```lua\nreturn true\n```" } } } },
      usage = { input_tokens = 4, output_tokens = 2 },
    }, nil)
    assert.is_nil(request_error)
    assert.are.equal("return true", response.parse(generated).code)

    request.send(body, function(_, err)
      request_error = err
    end)
    requests[2].callback({ error = { message = "upstream unavailable" } }, nil)
    assert.are.equal("upstream unavailable", response.parse({ error = { message = "upstream unavailable" } }).error)
    assert.is_nil(request_error)

    local cancelled = request.send(body, function()
      callback_count = callback_count + 1
    end)
    cancelled.cancel()
    requests[3].callback({ output_text = "late" }, nil)
    assert.is_true(requests[3].cancelled)
    assert.are.equal(1, callback_count)
  end)

  it("keeps ChatGPT tokens out of credential metadata while preserving model preference", function()
    local credentials = require("codetyper.config.credentials")
    local result = credentials.sanitize({
      providers = {
        openai = {
          model = "gpt-5.5",
          access_token = "access-secret",
          refresh_token = "refresh-secret",
          account_id = "account-id",
          residency = "eu-west",
          headers = { "Authorization: Bearer access-secret" },
          tokens = { access_token = "nested-access-secret", refresh_token = "nested-refresh-secret" },
          endpoint = "https://untrusted.example",
        },
      },
    })

    assert.are.equal("gpt-5.5", result.providers.openai.model)
    assert.is_nil(result.providers.openai.access_token)
    assert.is_nil(result.providers.openai.refresh_token)
    assert.is_nil(result.providers.openai.account_id)
    assert.is_nil(result.providers.openai.residency)
    assert.is_nil(result.providers.openai.headers)
    assert.is_nil(result.providers.openai.tokens)
    assert.is_nil(result.providers.openai.endpoint)
    assert.is_false(vim.inspect(result):find("access-secret", 1, true) ~= nil)
    assert.is_false(vim.inspect(result):find("nested-access-secret", 1, true) ~= nil)
    assert.is_false(vim.inspect(result):find("untrusted.example", 1, true) ~= nil)
  end)

  it("returns provider metadata with generated subscription text", function()
    local http, requests = request_stub()
    local auth = auth_stub()
    package.loaded["codetyper.core.llm.shared.http"] = http
    package.loaded["codetyper.core.llm.providers.openai.auth"] = auth
    local client = require("codetyper.core.llm.providers.openai")
    local generated, generation_error, metadata

    client.generate("prompt", { model = "gpt-5.5", system_prompt = "system" }, function(text, err, result)
      generated, generation_error, metadata = text, err, result
    end)
    requests[1].callback({ output_text = "return true", usage = { input_tokens = 1, output_tokens = 1 } }, nil)

    assert.are.equal("return true", generated)
    assert.is_nil(generation_error)
    assert.are.equal("openai", metadata.provider)
    assert.is_true(metadata.subscription)
    assert.are.equal("opencode-codex-allowlist-v1", metadata.catalog_version)
  end)
end)
