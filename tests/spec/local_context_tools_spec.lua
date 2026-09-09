--- Tests for the safe CodeGraph and TokenSave local JSON adapters.

local codegraph = require("codetyper.core.agent.tools.codegraph")
local local_cli = require("codetyper.core.agent.tools.local_cli")
local tokensave = require("codetyper.core.agent.tools.tokensave")

local function make_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_json(path, value)
  local file = assert(io.open(path, "w"))
  file:write(vim.json.encode(value))
  file:close()
end

local function make_cli(responses)
  local cli = { calls = {}, responses = responses }

  function cli.run(argv, opts, callback)
    table.insert(cli.calls, { argv = vim.deepcopy(argv), opts = opts })
    local response = table.remove(cli.responses, 1) or { stdout = "", stderr = "", exit_code = 0 }
    callback(response)
    return { cancel = function() end }
  end

  return cli
end

local function argv_contains_forbidden(argv)
  local forbidden = {
    init = true,
    sync = true,
    index = true,
    daemon = true,
    serve = true,
    wipe = true,
  }
  for _, value in ipairs(argv) do
    if forbidden[value] then
      return true
    end
  end
  return false
end

describe("local CLI runner", function()
  it("uses an argv array, bounds output, and completes cancellation once", function()
    local finish
    local stopped = false
    local completions = 0
    local handle = local_cli.run({ "codegraph", "status", "--json", "/tmp/project" }, {
      max_stdout = 8,
      max_stderr = 6,
      runner = function(argv, _, callback)
        assert.are.same({ "codegraph", "status", "--json", "/tmp/project" }, argv)
        finish = callback
        return {
          cancel = function()
            stopped = true
          end,
        }
      end,
    }, function(result)
      completions = completions + 1
      assert.is_true(result.cancelled)
    end)

    handle.cancel()
    assert.is_true(stopped)
    assert.are.equal(1, completions)

    finish({ stdout = string.rep("x", 20), stderr = string.rep("e", 20), exit_code = 0 })
    assert.are.equal(1, completions)
  end)

  it("times out an injected runner and invokes its cancellation hook", function()
    local stopped = false
    local result
    local handle = local_cli.run({ "tokensave", "status", "--json" }, {
      timeout_ms = 5,
      runner = function()
        return {
          cancel = function()
            stopped = true
          end,
        }
      end,
    }, function(value)
      result = value
    end)

    vim.wait(100, function()
      return result ~= nil
    end)
    handle.cancel()

    assert.is_true(stopped)
    assert.is_true(result.timed_out)
    assert.is_false(result.cancelled)
  end)
end)

describe("CodeGraph adapter", function()
  it("checks initialized status before context and builds fixed read-only argv", function()
    local root = make_tmp_dir()
    local cli = make_cli({
      { stdout = vim.json.encode({ initialized = true, lastIndexed = "2026-09-09T00:00:00Z" }), exit_code = 0 },
      { stdout = vim.json.encode({ summary = "request flow", entryPoints = { { name = "request" } } }), exit_code = 0 },
    })
    local result

    codegraph.context({ query = "request flow", max_nodes = 3, no_code = true }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("available", result.status)
    assert.are.equal("request flow", result.data.summary)
    assert.is_false(result.stale)
    assert.are.same({ "codegraph", "status", "--json", root }, cli.calls[1].argv)
    assert.are.same({
      "codegraph",
      "context",
      "request flow",
      "--path",
      root,
      "--format",
      "json",
      "--max-nodes",
      "3",
      "--no-code",
    }, cli.calls[2].argv)
    for _, call in ipairs(cli.calls) do
      assert.is_false(argv_contains_forbidden(call.argv))
      assert.are.equal(root, call.opts.cwd)
    end
  end)

  it("exposes explore with the same bounded read-only policy", function()
    local root = make_tmp_dir()
    local cli = make_cli({
      { stdout = vim.json.encode({ initialized = true, stale = true }), exit_code = 0 },
      { stdout = vim.json.encode({ nodes = { { name = "explore" } } }), exit_code = 0 },
    })
    local result

    codegraph.explore({ query = "explore", max_nodes = 2 }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("stale", result.status)
    assert.is_true(result.stale)
    assert.is_nil(result.data)
    assert.are.equal(1, #cli.calls)
  end)

  it("does not query an uninitialized, pending, or malformed index", function()
    local cases = {
      { value = { initialized = false }, status = "unavailable" },
      { value = { initialized = true, pending = true }, status = "stale" },
      { value = "not json", status = "error" },
    }

    for _, case in ipairs(cases) do
      local cli = make_cli({
        {
          stdout = type(case.value) == "string" and case.value or vim.json.encode(case.value),
          exit_code = 0,
        },
      })
      local result
      codegraph.context({ query = "request" }, function(value)
        result = value
      end, {
        root = make_tmp_dir(),
        cli = cli,
        executable = function()
          return true
        end,
      })

      assert.are.equal(case.status, result.status)
      assert.are.equal(1, #cli.calls)
    end
  end)

  it("rejects invalid query and limits before executable or CLI access", function()
    local called = false
    local cli = {
      run = function()
        called = true
      end,
    }

    local result
    codegraph.context({ query = "\0unsafe", max_nodes = 0 }, function(value)
      result = value
    end, {
      root = make_tmp_dir(),
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("error", result.status)
    assert.is_false(called)
  end)

  it("cancels the active query after status has completed", function()
    local root = make_tmp_dir()
    local query_cancelled = false
    local query_callback
    local call_count = 0
    local cli = {
      run = function(argv, opts, callback)
        call_count = call_count + 1
        if call_count == 1 then
          callback({
            stdout = vim.json.encode({ initialized = true }),
            stderr = "",
            exit_code = 0,
          })
        else
          query_callback = callback
          return {
            cancel = function()
              query_cancelled = true
            end,
          }
        end
        return { cancel = function() end }
      end,
    }
    local result
    local handle = codegraph.context({ query = "request" }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    handle.cancel()
    assert.is_true(query_cancelled)
    assert.are.equal("cancelled", result.status)
    assert.is_not_nil(query_callback)
  end)
end)

describe("TokenSave adapter", function()
  local function make_tokensave_root(branch)
    local root = make_tmp_dir()
    vim.fn.mkdir(root .. "/.tokensave", "p")
    write_json(root .. "/.tokensave/config.json", { root_dir = root })
    write_json(root .. "/.tokensave/branch-meta.json", {
      [branch] = { db_file = "tokensave.db" },
    })
    return root
  end

  it("checks project and branch state, then parses bare JSON search output", function()
    local root = make_tokensave_root("main")
    local cli = make_cli({
      { stdout = "main\n", exit_code = 0 },
      { stdout = vim.json.encode({ initialized = true, status = "ready" }), exit_code = 0 },
      { stdout = vim.json.encode({ { file = "lua/request.lua", line = 4 } }), exit_code = 0 },
    })
    local result

    tokensave.search({ query = "request", limit = 5 }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("available", result.status)
    assert.are.equal("lua/request.lua", result.data[1].file)
    assert.is_false(result.stale)
    assert.are.same(
      { "tokensave", "tool", "search", "--query", "request", "--limit", "5", "--json" },
      cli.calls[3].argv
    )
    for _, call in ipairs(cli.calls) do
      assert.is_false(argv_contains_forbidden(call.argv))
      assert.are.equal(root, call.opts.cwd)
    end
  end)

  it("unwraps the observed content[1].text double-encoded JSON envelope", function()
    local root = make_tokensave_root("feature")
    local inner = vim.json.encode({ { symbol = "resolve", file = "lua/resolve.lua" } })
    local cli = make_cli({
      { stdout = "feature\n", exit_code = 0 },
      { stdout = vim.json.encode({ initialized = true, status = "ready" }), exit_code = 0 },
      {
        stdout = vim.json.encode({
          content = {
            { type = "text", text = "ignored" },
            { type = "text", text = inner },
          },
        }),
        exit_code = 0,
      },
    })
    local result

    tokensave.search({ query = "resolve", limit = 2 }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("available", result.status)
    assert.are.equal("resolve", result.data[1].symbol)
  end)

  it("returns stale without searching when the current branch is unmapped", function()
    local root = make_tokensave_root("main")
    local cli = make_cli({ { stdout = "detached\n", exit_code = 0 } })
    local result

    tokensave.search({ query = "request", limit = 3 }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("stale", result.status)
    assert.is_true(result.stale)
    assert.are.equal(1, #cli.calls)
  end)

  it("requires markers and validates bounded input without touching a CLI", function()
    local root = make_tmp_dir()
    local called = false
    local cli = {
      run = function()
        called = true
      end,
    }
    local result

    tokensave.search({ query = "", limit = 101 }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("error", result.status)
    assert.is_false(called)

    tokensave.search({ query = "request", limit = 2 }, function(value)
      result = value
    end, {
      root = root,
      cli = cli,
      executable = function()
        return true
      end,
    })

    assert.are.equal("unavailable", result.status)
    assert.is_false(called)
  end)
end)
