local parse_response = require("codetyper.core.agent.parse_response")
local executor = require("codetyper.core.agent.executor")
local agent_loop = require("codetyper.core.agent.loop")

local function registry_stub(events, pending)
  return {
    dispatch = function(name, args, callback)
      events[#events + 1] = "local:" .. name
      if pending then
        pending[name] = callback
        return {
          cancel = function()
            events[#events + 1] = "cancel:" .. name
          end,
        }
      end
      callback({
        status = "available",
        data = { name = name, args = args },
        error = nil,
        stale = false,
      })
      return { cancel = function() end }
    end,
  }
end

local function mcp_stub(events)
  return {
    decode_tool_name = function(encoded)
      return encoded:match("^(.-)__(.+)$")
    end,
    is_tool_allowed = function(server, tool)
      return server == "remote" and tool == "lookup"
    end,
    call_tool = function(server, tool, args, callback)
      events[#events + 1] = "mcp:" .. server .. "/" .. tool
      callback(vim.json.encode({ server = server, tool = tool, args = args }), nil)
      return { cancel = function() end }
    end,
  }
end

describe("agent dispatch parity", function()
  it("parses only canonical local TOOL markers into registry calls", function()
    local response = table.concat({
      'TOOL:CODEGRAPH {"query":"needle","max_nodes":4}',
      'TOOL:ASK_USER {"question":"Pick one","options":["A","B"]}',
      'TOOL:UNKNOWN {"command":"echo unsafe"}',
      'TOOL:MCP remote/lookup {"query":"needle"}',
    }, "\n")

    local _, is_agent, calls = parse_response(response, "/tmp/project", nil)

    assert.is_true(is_agent)
    assert.are.equal(3, #calls)
    assert.are.equal("registry", calls[1].type)
    assert.are.equal("codegraph_context", calls[1].name)
    assert.are.same({ query = "needle", max_nodes = 4 }, calls[1].args)
    assert.are.equal("registry", calls[2].type)
    assert.are.equal("ask_user", calls[2].name)
    assert.are.equal("mcp", calls[3].type)
  end)

  it("uses the same registry result for text markers and native structured calls", function()
    local text_events = {}
    local native_events = {}
    local text_registry = registry_stub(text_events)
    local native_registry = registry_stub(native_events)
    local text_mcp = mcp_stub(text_events)
    local native_mcp = mcp_stub(native_events)
    local text_calls = {
      {
        type = "registry",
        name = "codegraph_context",
        args = { query = "needle", max_nodes = 4 },
      },
    }
    local native_calls = {
      {
        id = "native-1",
        type = "function",
        ["function"] = {
          name = "codegraph_context",
          arguments = vim.json.encode({ query = "needle", max_nodes = 4 }),
        },
      },
    }
    local text_results
    local native_results

    executor.execute_tools(text_calls, function(results)
      text_results = results
    end, { registry = text_registry, mcp = text_mcp })
    executor.execute_tools(native_calls, function(results)
      native_results = results
    end, { registry = native_registry, mcp = native_mcp })

    assert.are.equal(1, #text_results)
    assert.are.equal(1, #native_results)
    assert.are.same(text_results[1].result, native_results[1].result)
    assert.are.equal("available", native_results[1].result.status)
    assert.are.equal("codegraph_context", native_results[1].name)
  end)

  it("runs local registry tools before remote MCP and keeps result order", function()
    local events = {}
    local calls = {
      {
        id = "remote-1",
        name = "remote__lookup",
        arguments = { query = "needle" },
      },
      {
        id = "local-1",
        name = "tokensave_search",
        arguments = { query = "needle", limit = 2 },
      },
    }
    local results

    executor.execute_tools(calls, function(value)
      results = value
    end, { registry = registry_stub(events), mcp = mcp_stub(events) })

    assert.are.same({ "local:tokensave_search", "mcp:remote/lookup" }, events)
    assert.are.equal("remote__lookup", results[1].name)
    assert.are.equal("tokensave_search", results[2].name)
    assert.are.equal("available", results[2].result.status)
  end)

  it("rejects unknown native tools and disallowed MCP tools without execution", function()
    local events = {}
    local results

    executor.execute_tools({
      { id = "unknown", name = "run_anything", arguments = { command = "echo unsafe" } },
      { id = "blocked", name = "remote__shell", arguments = { command = "echo unsafe" } },
    }, function(value)
      results = value
    end, { registry = registry_stub(events), mcp = mcp_stub(events) })

    assert.are.same({}, events)
    assert.are.equal("error", results[1].result.status)
    assert.are.equal("error", results[2].result.status)
  end)

  it("caps local results and completes exactly once across late callbacks", function()
    local pending = {}
    local events = {}
    local completed = 0
    local final_result
    local handle = executor.execute_tools({
      { id = "pending", name = "codegraph_context", arguments = { query = "needle" } },
    }, function(results)
      completed = completed + 1
      final_result = results
    end, { registry = registry_stub(events, pending), timeout_ms = 20 })

    vim.wait(200, function()
      return completed == 1
    end, 10)
    assert.are.equal(1, completed)
    assert.are.equal("timeout", final_result[1].result.status)
    assert.are.same({ "local:codegraph_context", "cancel:codegraph_context" }, events)
    handle.cancel()

    pending.codegraph_context({
      status = "available",
      data = string.rep("x", 5000),
      error = nil,
      stale = false,
    })
    assert.are.equal(1, completed)
  end)

  it("routes native calls through the shared executor and propagates cancellation", function()
    local pending = {}
    local completed = 0
    local final_result
    local handle = agent_loop.execute_native_tools({
      {
        id = "native-1",
        type = "function",
        ["function"] = {
          name = "ask_user",
          arguments = vim.json.encode({ question = "Pick", options = { "A", "B" } }),
        },
      },
    }, function(results)
      completed = completed + 1
      final_result = results
    end, { registry = registry_stub({}, pending) })

    handle.cancel()
    assert.are.equal(1, completed)
    assert.are.equal("cancelled", vim.json.decode(final_result[1].content).status)

    pending.ask_user({
      status = "selected",
      data = { index = 1, option = "A" },
      error = nil,
      stale = false,
    })
    assert.are.equal(1, completed)
  end)

  it("serializes mutating registry calls without overlapping callbacks", function()
    local callbacks = {}
    local active = 0
    local maximum_active = 0
    local dispatches = 0
    local registry = {
      dispatch = function(name, _, callback)
        dispatches = dispatches + 1
        active = active + 1
        maximum_active = math.max(maximum_active, active)
        callbacks[#callbacks + 1] = function(value)
          active = active - 1
          callback(value)
        end
        return { cancel = function() end }
      end,
    }
    local completed

    executor.execute_tools({
      { name = "add_import", arguments = { path = "a.lua", statement = "local A = 1" } },
      { name = "add_import", arguments = { path = "b.lua", statement = "local B = 1" } },
    }, function(results)
      completed = results
    end, { registry = registry })

    assert.are.equal(1, dispatches)
    assert.are.equal(1, #callbacks)
    callbacks[1]({ status = "available", data = { changed = true }, stale = false })
    assert.are.equal(2, dispatches)
    assert.are.equal(2, #callbacks)
    callbacks[2]({ status = "available", data = { changed = true }, stale = false })

    assert.are.equal(1, maximum_active)
    assert.are.equal("available", completed[1].result.status)
    assert.are.equal("available", completed[2].result.status)
  end)
end)
