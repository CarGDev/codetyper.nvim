--- Tests for the Context7 MCPHub and OpenCode-compatible transports.

local context7 = require("codetyper.core.agent.tools.context7")
local transport = require("codetyper.core.agent.tools.context7_transport")
local tools = require("codetyper.core.agent.tools")

local function json(value)
  return vim.json.encode(value)
end

local function response(value, headers, status)
  return {
    status = status or 200,
    headers = headers or {},
    body = type(value) == "string" and value or json(value),
  }
end

local function make_transport(responses)
  local fake = { requests = {}, cancellations = 0 }

  function fake.request(request, callback)
    table.insert(fake.requests, vim.deepcopy(request))
    local next_response = table.remove(responses, 1)
    if next_response then
      callback(next_response)
    end
    return {
      cancel = function()
        fake.cancellations = fake.cancellations + 1
      end,
    }
  end

  return fake
end

local function make_hub(state, available_tools, call)
  return {
    get_hub_state = function()
      return state
    end,
    get_hub_tools = function()
      return available_tools
    end,
    call_tool = call,
  }
end

local function request_method(request)
  return request.payload and request.payload.method
end

local function decode_request(request)
  request.payload = vim.json.decode(request.body)
  return request.payload
end

local function has_header(request, name, expected)
  return request.headers and request.headers[name] == expected
end

describe("Context7 transport", function()
  it("decodes bounded JSON and SSE MCP responses", function()
    local value, err = transport.decode_response(json({ jsonrpc = "2.0", id = 1, result = { ok = true } }), {})

    assert.is_nil(err)
    assert.is_true(value.result.ok)

    local sse = "event: message\ndata: " .. json({ jsonrpc = "2.0", id = 2, result = { ok = "sse" } }) .. "\n\n"
    local streamed, stream_error = transport.decode_response(sse, { ["content-type"] = "text/event-stream" })

    assert.is_nil(stream_error)
    assert.are.equal("sse", streamed.result.ok)

    local oversized, oversized_error = transport.decode_response(string.rep("x", 100), {}, { max_body = 32 })
    assert.is_nil(oversized)
    assert.are.equal("response body exceeds the configured bound", oversized_error)
  end)

  it("builds only the initialize, initialized, list, and allowlisted call messages", function()
    local initialize = transport.build_initialize(1)
    assert.are.equal("initialize", initialize.method)
    assert.are.equal("2024-11-05", initialize.params.protocolVersion)
    assert.are.same({}, initialize.params.capabilities)
    assert.is_string(initialize.params.clientInfo.name)

    local notification = transport.build_initialized_notification()
    assert.are.equal("notifications/initialized", notification.method)
    assert.is_nil(notification.id)

    local list = transport.build_tools_list(2)
    assert.are.equal("tools/list", list.method)

    local call = transport.build_tool_call(3, "resolve-library-id", { query = "lua" })
    assert.are.equal("tools/call", call.method)
    assert.are.equal("resolve-library-id", call.params.name)

    local denied, denied_error = transport.build_tool_call(4, "shell", { command = "cat" })
    assert.is_nil(denied)
    assert.are.equal("Context7 tool is not allowlisted", denied_error)

    local arbitrary, arbitrary_error = transport.build_message(5, "resources/read", {})
    assert.is_nil(arbitrary)
    assert.are.equal("MCP method is not allowlisted", arbitrary_error)
  end)
end)

describe("Context7 adapter", function()
  it("uses a ready mcphub Context7 tool before the remote fallback", function()
    local calls = {}
    local hub = make_hub({ status = "ready" }, {
      { server_name = "context7", name = "resolve-library-id" },
      { server_name = "context7", name = "query-docs" },
    }, function(server, name, arguments, callback)
      table.insert(calls, { server = server, name = name, arguments = arguments })
      callback({ result = { content = { { type = "text", text = json({ libraries = { { id = "lua/lua" } } }) } } } })
    end)
    local remote = make_transport({})
    local result

    context7.resolve({ query = "lua" }, function(value)
      result = value
    end, {
      mcp = hub,
      transport = remote,
      api_key_provider = function()
        return "should-not-be-read"
      end,
    })

    assert.are.equal("available", result.status)
    assert.are.equal("lua/lua", result.data.libraries[1].id)
    assert.are.equal("context7", calls[1].server)
    assert.are.equal("resolve-library-id", calls[1].name)
    assert.are.equal("lua", calls[1].arguments.query)
    assert.are.equal(0, #remote.requests)
  end)

  it("falls back through initialize, session headers, notification, list, and SSE call", function()
    local secret = "context7-test-secret"
    local remote = make_transport({
      response(
        { jsonrpc = "2.0", id = 1, result = { protocolVersion = "2024-11-05" } },
        { ["Mcp-Session-Id"] = "session-123" }
      ),
      response("", { ["Mcp-Session-Id"] = "session-123" }, 202),
      response({
        jsonrpc = "2.0",
        id = 2,
        result = { tools = { { name = "resolve-library-id" }, { name = "query-docs" } } },
      }, { ["Mcp-Session-Id"] = "session-123" }),
      response("event: message\ndata: " .. json({
        jsonrpc = "2.0",
        id = 3,
        result = { content = { { type = "text", text = json({ libraries = { { id = "lua/lua" } } }) } } },
      }) .. "\n\n", { ["Mcp-Session-Id"] = "session-123", ["content-type"] = "text/event-stream" }),
    })
    local unavailable_hub = make_hub({ status = "absent" }, {}, function()
      error("hub must not be called")
    end)
    local result

    context7.resolve({ query = "lua" }, function(value)
      result = value
    end, {
      mcp = unavailable_hub,
      transport = remote,
      api_key_provider = function()
        return secret
      end,
    })

    assert.are.equal("available", result.status)
    assert.are.equal("lua/lua", result.data.libraries[1].id)
    assert.are.equal("fallback", result.metadata.source)
    assert.are.equal("absent", result.metadata.hub_status)
    assert.are.equal(4, #remote.requests)

    local initialize = decode_request(remote.requests[1])
    assert.are.equal(transport.DEFAULT_URL, remote.requests[1].url)
    assert.are.equal("POST", remote.requests[1].method)
    assert.are.equal("initialize", request_method(remote.requests[1]))
    assert.are.equal("2024-11-05", initialize.params.protocolVersion)
    assert.are.same({}, initialize.params.capabilities)
    assert.are.equal("Bearer " .. secret, remote.requests[1].headers.Authorization)

    local notification = decode_request(remote.requests[2])
    assert.are.equal("notifications/initialized", notification.method)
    assert.is_nil(notification.id)
    assert.is_true(has_header(remote.requests[2], "Mcp-Session-Id", "session-123"))

    local listed = decode_request(remote.requests[3])
    assert.are.equal("tools/list", listed.method)
    assert.is_true(has_header(remote.requests[3], "Mcp-Session-Id", "session-123"))

    local called = decode_request(remote.requests[4])
    assert.are.equal("tools/call", called.method)
    assert.are.equal("resolve-library-id", called.params.name)
    assert.are.equal("lua", called.params.arguments.query)
    assert.is_true(has_header(remote.requests[4], "Mcp-Session-Id", "session-123"))
    assert.is_false(vim.inspect(result):find(secret, 1, true) ~= nil)
  end)

  it("uses the registry result contract and preserves safe remote error metadata", function()
    local remote = make_transport({
      response({ jsonrpc = "2.0", id = 1, result = {} }, { ["Mcp-Session-Id"] = "session-error" }),
      response("", { ["Mcp-Session-Id"] = "session-error" }, 202),
      response({ jsonrpc = "2.0", id = 2, result = { tools = { { name = "query-docs" } } } }),
    })
    local hub = make_hub({ status = "not_ready" }, {}, function()
      error("hub must not be called")
    end)
    local result

    tools.dispatch("context7_resolve_library", { query = "lua" }, function(value)
      result = value
    end, {
      mcp = hub,
      transport = remote,
      api_key_provider = function()
        return "registry-secret"
      end,
    })

    assert.are.equal("unavailable", result.status)
    assert.is_nil(result.data)
    assert.is_true(result.stale)
    assert.are.equal("fallback", result.metadata.source)
    assert.are.equal("not_ready", result.metadata.hub_status)
    assert.is_string(result.error)
    assert.is_false(vim.inspect(result):find("registry-secret", 1, true) ~= nil)
  end)

  it("rejects missing or arbitrary remote tools without making a forbidden call", function()
    local remote = make_transport({
      response({ jsonrpc = "2.0", id = 1, result = {} }, { ["Mcp-Session-Id"] = "session-missing" }),
      response("", { ["Mcp-Session-Id"] = "session-missing" }, 202),
      response({ jsonrpc = "2.0", id = 2, result = { tools = { { name = "shell" } } } }),
    })
    local result

    context7.query({ library_id = "lua/lua", query = "tables" }, function(value)
      result = value
    end, {
      mcp = make_hub({ status = "absent" }, {}, function()
        error("hub must not be called")
      end),
      transport = remote,
      api_key_provider = function()
        return "missing-tool-secret"
      end,
    })

    assert.are.equal("unavailable", result.status)
    assert.is_true(result.stale)
    assert.are.equal(3, #remote.requests)
    assert.is_nil(remote.requests[4])
    assert.is_false(vim.inspect(result):find("missing-tool-secret", 1, true) ~= nil)
  end)

  it("returns explicit errors for hub execution failures and remote protocol failures", function()
    local hub_result
    local hub = make_hub(
      { status = "ready" },
      { { server_name = "context7", name = "query-docs" } },
      function(_, _, _, callback)
        callback(nil, "remote API key leaked in a provider error")
      end
    )

    context7.query({ library_id = "lua/lua", query = "tables" }, function(value)
      hub_result = value
    end, {
      mcp = hub,
      transport = make_transport({}),
      api_key_provider = function()
        return "hub-secret"
      end,
    })

    assert.are.equal("error", hub_result.status)
    assert.is_true(hub_result.stale)
    assert.is_string(hub_result.error)
    assert.is_false(vim.inspect(hub_result):find("hub-secret", 1, true) ~= nil)

    local remote_result
    local remote =
      make_transport({ response({ jsonrpc = "2.0", id = 1, error = { code = -32000, message = "denied" } }) })
    context7.resolve({ query = "lua" }, function(value)
      remote_result = value
    end, {
      mcp = make_hub({ status = "absent" }, {}, function()
        error("hub must not be called")
      end),
      transport = remote,
      api_key_provider = function()
        return "protocol-secret"
      end,
    })

    assert.are.equal("error", remote_result.status)
    assert.is_true(remote_result.stale)
    assert.are.equal(1, #remote.requests)
    assert.is_false(vim.inspect(remote_result):find("protocol-secret", 1, true) ~= nil)
  end)

  it("supports cancellation and timeout without late callbacks", function()
    local pending = make_transport({ nil })
    local result
    local handle = context7.resolve({ query = "lua" }, function(value)
      result = value
    end, {
      mcp = make_hub({ status = "absent" }, {}, function()
        error("hub must not be called")
      end),
      transport = pending,
      timeout_ms = 1000,
      api_key_provider = function()
        return "cancel-secret"
      end,
    })

    handle.cancel()
    assert.are.equal("cancelled", result.status)
    assert.are.equal(1, pending.cancellations)

    local timeout_transport = make_transport({ nil })
    local timeout_result
    context7.resolve({ query = "lua" }, function(value)
      timeout_result = value
    end, {
      mcp = make_hub({ status = "absent" }, {}, function()
        error("hub must not be called")
      end),
      transport = timeout_transport,
      timeout_ms = 5,
      api_key_provider = function()
        return "timeout-secret"
      end,
    })

    vim.wait(100, function()
      return timeout_result ~= nil
    end)
    assert.are.equal("error", timeout_result.status)
    assert.is_truthy(timeout_result.error:find("timed out", 1, true))
    assert.are.equal(1, timeout_transport.cancellations)
    assert.is_false(vim.inspect(timeout_result):find("timeout-secret", 1, true) ~= nil)
  end)

  it("does not start an unauthenticated default network request", function()
    local result
    context7.resolve({ query = "lua" }, function(value)
      result = value
    end, { mcp = make_hub({ status = "absent" }, {}, function() end) })

    assert.are.equal("unavailable", result.status)
    assert.is_true(result.stale)
    assert.is_nil(result.data)
  end)
end)
