--- Tests for the provider-agnostic agent tool registry.

local tools = require("codetyper.core.agent.tools")

local EXPECTED_TOOLS = {
  "codegraph_context",
  "tokensave_search",
  "context7_resolve_library",
  "context7_query_docs",
  "ask_user",
  "add_import",
}

local function names(entries)
  local result = {}
  for _, entry in ipairs(entries) do
    table.insert(result, entry.name)
  end
  return result
end

describe("agent tool registry", function()
  it("lists the six canonical provider-agnostic schemas in order", function()
    local entries = tools.list()

    assert.are.same(EXPECTED_TOOLS, names(entries))
    for _, entry in ipairs(entries) do
      assert.are.equal("function", entry.type)
      assert.are.equal("object", entry.parameters.type)
      assert.are.same(entry.parameters, entry.schema)
      assert.are.same(entry.parameters, entry.inputSchema)
      assert.is_false(entry.parameters.additionalProperties)
      assert.is_table(entry.parameters.properties)
      assert.is_true(#entry.parameters.required > 0)
    end
  end)

  it("validates bounded local inputs and rejects unknown or extra fields", function()
    local valid, normalized = tools.validate("codegraph_context", {
      query = "find the request builder",
      max_nodes = 4,
      no_code = true,
    })

    assert.is_true(valid)
    assert.are.same({
      query = "find the request builder",
      max_nodes = 4,
      no_code = true,
    }, normalized)

    local invalid_query, query_error = tools.validate("codegraph_context", { query = "\n" })
    assert.is_false(invalid_query)
    assert.is_string(query_error)

    local invalid_limit, limit_error = tools.validate("tokensave_search", { query = "x", limit = 0 })
    assert.is_false(invalid_limit)
    assert.is_string(limit_error)

    local extra, extra_error = tools.validate("tokensave_search", { query = "x", limit = 1, shell = "cat" })
    assert.is_false(extra)
    assert.is_string(extra_error)

    local unknown, unknown_error = tools.validate("shell", { command = "not allowed" })
    assert.is_false(unknown)
    assert.is_string(unknown_error)
  end)

  it("returns a bounded unavailable result for deferred tools", function()
    local result
    tools.dispatch("context7_resolve_library", { query = "lua" }, function(value)
      result = value
    end)

    assert.are.equal("unavailable", result.status)
    assert.is_true(result.stale)
    assert.is_nil(result.data)
    assert.is_string(result.error)
    assert.is_true(#result.error <= 512)
  end)

  it("uses an injected adapter while preserving the shared result contract", function()
    local result
    tools.dispatch("codegraph_context", { query = "request", max_nodes = 2 }, function(value)
      result = value
    end, {
      adapters = {
        codegraph_context = function(args, callback)
          callback({
            status = "available",
            data = { query = args.query, nodes = 2 },
            error = nil,
            stale = false,
          })
        end,
      },
    })

    assert.are.same({ query = "request", nodes = 2 }, result.data)
    assert.are.equal("available", result.status)
    assert.is_false(result.stale)
  end)

  it("reports availability metadata without exposing command details", function()
    local metadata = tools.availability()

    assert.are.equal(6, #metadata)
    for _, entry in ipairs(metadata) do
      assert.is_string(entry.name)
      assert.is_boolean(entry.available)
      assert.is_boolean(entry.stale)
      assert.is_nil(entry.command)
    end
  end)
end)
