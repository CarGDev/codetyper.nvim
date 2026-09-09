local CLAUDE_MODULES = {
  "codetyper.core.llm.providers.claude",
  "codetyper.core.llm.providers.claude.init",
  "codetyper.core.llm.providers.claude.models",
  "codetyper.core.llm.providers.claude.request",
  "codetyper.core.llm.providers.claude.response",
  "codetyper.core.llm.providers.ollama.models",
}

local INJECTED_MODULES = {
  "codetyper.core.llm.shared.http",
  "codetyper.support.flog",
  "codetyper.support.utils",
  "codetyper.config.credentials",
}

local function stub_http()
  local requests = {}
  local http = {}

  local function add_request(method, url, headers, body, callback)
    local request = {
      method = method,
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

  function http.get(url, headers, callback)
    return add_request("GET", url, headers, nil, callback)
  end

  function http.post(url, headers, body, callback)
    return add_request("POST", url, headers, body, callback)
  end

  return http, requests
end

local function load_claude(http)
  package.loaded["codetyper.core.llm.shared.http"] = http
  for _, module_name in ipairs(CLAUDE_MODULES) do
    package.loaded[module_name] = nil
  end

  local ok, modules = pcall(function()
    return {
      client = require("codetyper.core.llm.providers.claude"),
      models = require("codetyper.core.llm.providers.claude.models"),
      request = require("codetyper.core.llm.providers.claude.request"),
      response = require("codetyper.core.llm.providers.claude.response"),
    }
  end)
  assert.is_true(ok, modules)
  return modules
end

local function load_ollama_models(http)
  package.loaded["codetyper.core.llm.shared.http"] = http
  package.loaded["codetyper.core.llm.providers.ollama.models"] = nil
  local ok, models = pcall(require, "codetyper.core.llm.providers.ollama.models")
  assert.is_true(ok, models)
  return models
end

describe("Anthropic provider", function()
  local original_env, original_modules

  before_each(function()
    original_env = vim.env.ANTHROPIC_API_KEY
    vim.env.ANTHROPIC_API_KEY = nil
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
    package.loaded["codetyper.config.credentials"] = {
      save = function()
        error("Anthropic credentials must not be persisted")
      end,
    }
  end)

  after_each(function()
    vim.env.ANTHROPIC_API_KEY = original_env
    for _, module_name in ipairs(CLAUDE_MODULES) do
      package.loaded[module_name] = nil
    end
    for _, module_name in ipairs(INJECTED_MODULES) do
      package.loaded[module_name] = original_modules[module_name]
    end
  end)

  it("uses only the inherited key and sends exact model discovery headers", function()
    vim.env.ANTHROPIC_API_KEY = "unit-test-anthropic-secret"
    local http, requests = stub_http()
    local modules = load_claude(http)
    local models, request_error

    modules.models.fetch(function(result, err)
      models, request_error = result, err
    end)

    assert.are.equal("GET", requests[1].method)
    assert.are.equal("https://api.anthropic.com/v1/models", requests[1].url)
    assert.same({
      "x-api-key: unit-test-anthropic-secret",
      "anthropic-version: 2023-06-01",
    }, requests[1].headers)

    requests[1].callback({
      data = {
        { id = "claude-sonnet-4-5", display_name = "Claude Sonnet 4.5" },
        { id = "claude-haiku-4-5" },
        { display_name = "malformed" },
      },
    }, nil)

    assert.is_nil(request_error)
    assert.same({
      {
        id = "claude-haiku-4-5",
        name = "claude-haiku-4-5",
        provider = "claude",
        capabilities = { streaming = false, tools = false },
      },
      {
        id = "claude-sonnet-4-5",
        name = "Claude Sonnet 4.5",
        provider = "claude",
        capabilities = { streaming = false, tools = false },
      },
    }, models)
  end)

  it("reports unavailable without an environment key and never reads or saves a secret", function()
    local http, requests = stub_http()
    local modules = load_claude(http)
    local models, request_error

    modules.models.fetch(function(result, err)
      models, request_error = result, err
    end)

    assert.is_nil(models)
    assert.are.equal("Anthropic unavailable: ANTHROPIC_API_KEY is not set", request_error)
    assert.is_nil(requests[1])

    local body, body_error = modules.request.build_body("claude-sonnet-4-5", "system", "prompt")
    assert.is_nil(body_error)
    assert.is_false(vim.inspect(body):find("ANTHROPIC_API_KEY", 1, true) ~= nil)
    assert.is_false(vim.inspect(body):find("unit-test-anthropic-secret", 1, true) ~= nil)
  end)

  it("normalizes partial data and preserves empty and error outcomes", function()
    vim.env.ANTHROPIC_API_KEY = "unit-test-anthropic-secret"
    local http, requests = stub_http()
    local modules = load_claude(http)
    local result, request_error

    modules.models.fetch(function(models, err)
      result, request_error = models, err
    end)
    requests[1].callback({ data = { { id = "claude-3-7-sonnet" }, { id = "" } } }, nil)
    assert.are.equal(1, #result)
    assert.are.equal("claude-3-7-sonnet", result[1].id)
    assert.is_nil(request_error)

    modules.models.fetch(function(models, err)
      result, request_error = models, err
    end)
    requests[2].callback({ data = {} }, nil)
    assert.same({}, result)
    assert.is_nil(request_error)

    modules.models.fetch(function(models, err)
      result, request_error = models, err
    end)
    requests[3].callback(nil, "Anthropic unavailable")
    assert.is_nil(result)
    assert.are.equal("Anthropic unavailable", request_error)
  end)

  it("builds non-streaming messages and rejects streaming and tools", function()
    local http = stub_http()
    local modules = load_claude(http)
    local body, body_error = modules.request.build_body("claude-sonnet-4-5", "system", "prompt")

    assert.is_nil(body_error)
    assert.same({
      model = "claude-sonnet-4-5",
      max_tokens = 4096,
      system = "system",
      messages = { { role = "user", content = "prompt" } },
      stream = false,
    }, body)

    local streamed, stream_error = modules.request.build_body("claude-sonnet-4-5", "", "prompt", {
      stream = true,
    })
    assert.is_nil(streamed)
    assert.matches("streaming is not supported", stream_error)

    local tooled, tools_error = modules.request.build_body("claude-sonnet-4-5", "", "prompt", {
      tools = { { name = "terminal" } },
    })
    assert.is_nil(tooled)
    assert.matches("tools are not supported", tools_error)
  end)

  it("uses the common generation and error contract without logging or persisting credentials", function()
    vim.env.ANTHROPIC_API_KEY = "unit-test-anthropic-secret"
    local http, requests = stub_http()
    local log_messages = {}
    package.loaded["codetyper.support.flog"] = {
      info = function(_, message)
        log_messages[#log_messages + 1] = message
      end,
      warn = function(_, message)
        log_messages[#log_messages + 1] = message
      end,
      error = function(_, message)
        log_messages[#log_messages + 1] = message
      end,
      debug = function(_, message)
        log_messages[#log_messages + 1] = message
      end,
    }
    local modules = load_claude(http)
    local generated, generation_error, usage

    modules.client.generate("prompt", {
      model = "claude-sonnet-4-5",
      system_prompt = "system",
    }, function(text, err, token_usage)
      generated, generation_error, usage = text, err, token_usage
    end)

    assert.are.equal("POST", requests[1].method)
    assert.are.equal("https://api.anthropic.com/v1/messages", requests[1].url)
    assert.same({
      "x-api-key: unit-test-anthropic-secret",
      "anthropic-version: 2023-06-01",
      "content-type: application/json",
    }, requests[1].headers)
    local sent = vim.json.decode(requests[1].body)
    assert.is_false(sent.stream)
    assert.is_nil(sent.tools)
    assert.are.equal("claude-sonnet-4-5", sent.model)
    assert.are.equal("prompt", sent.messages[1].content)

    requests[1].callback({
      content = { { type = "text", text = "```lua\nreturn true\n```" } },
      usage = { input_tokens = 4, output_tokens = 2 },
    }, nil)
    assert.are.equal("return true", generated)
    assert.is_nil(generation_error)
    assert.same({ prompt_tokens = 4, completion_tokens = 2 }, usage)

    modules.client.generate("prompt", { model = "claude-sonnet-4-5" }, function(text, err)
      generated, generation_error = text, err
    end)
    requests[2].callback(nil, "upstream unavailable: unit-test-anthropic-secret")
    assert.is_nil(generated)
    assert.are.equal("upstream unavailable: [REDACTED]", generation_error)

    modules.client.generate("prompt", { model = "claude-sonnet-4-5" }, function(text, err)
      generated, generation_error = text, err
    end)
    requests[3].callback({
      type = "error",
      error = { message = "invalid request" },
    }, nil)
    assert.is_nil(generated)
    assert.are.equal("invalid request", generation_error)

    assert.is_true(#log_messages > 0, "expected captured Anthropic diagnostics")
    for _, message in ipairs(log_messages) do
      assert.is_false(message:find("unit-test-anthropic-secret", 1, true) ~= nil)
    end
  end)

  it("exposes Ollama tags as provider descriptors for the catalog seam", function()
    local http, requests = stub_http()
    local models = load_ollama_models(http)
    local result, request_error

    models.fetch("http://ollama.test", function(items, err)
      result, request_error = items, err
    end)
    assert.are.equal("GET", requests[1].method)
    assert.are.equal("http://ollama.test/api/tags", requests[1].url)
    assert.same({}, requests[1].headers)

    requests[1].callback({
      models = {
        { name = "llama3:8b", details = { family = "llama" } },
        { model = "qwen2.5-coder:7b", capabilities = { tools = false } },
        { name = "" },
      },
    }, nil)

    assert.is_nil(request_error)
    assert.same({
      {
        id = "llama3:8b",
        name = "llama3:8b",
        provider = "ollama",
        capabilities = { family = "llama" },
      },
      {
        id = "qwen2.5-coder:7b",
        name = "qwen2.5-coder:7b",
        provider = "ollama",
        capabilities = { tools = false },
      },
    }, result)
  end)
end)
