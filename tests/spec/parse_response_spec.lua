--- Tests for agent file operations: parsing canned LLM responses into
--- FILE:CREATE/MODIFY/DELETE operations and executing them against a real
--- temp directory. No LLM/network calls — response text is hand-written.
--- Covers: "inject files", "add imports correctly" (delivery pipeline only —
--- the plugin relies on the model to emit correct import lines; there is no
--- deterministic auto-merge logic to test beyond faithful application).

local parse_response = require("codetyper.core.agent.parse_response")
local executor = require("codetyper.core.agent.executor")

local function make_tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = io.open(path, "w")
  f:write(content)
  f:close()
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

describe("parse_response — FILE:CREATE", function()
  it("resolves a monorepo-style relative path using the target file's ancestor dir", function()
    local root = make_tmp_dir()
    -- Simulate monorepo: <root>/frontend/src/... with .git at <root>
    vim.fn.mkdir(root .. "/frontend/src/api", "p")
    local target_path = root .. "/frontend/src/api/existing.ts"
    write_file(target_path, "// existing file")

    local response = table.concat({
      "FILE:CREATE src/api/new_module.ts",
      "```typescript",
      "export function hello() { return 'hi'; }",
      "```",
    }, "\n")

    local ops, is_agent = parse_response(response, root, target_path)

    assert.is_true(is_agent)
    assert.are.equal(1, #ops)
    assert.are.equal("create", ops[1].action)
    -- Should resolve under frontend/ (inferred from target_path's ancestor "src"),
    -- not directly under root/src.
    assert.are.equal(root .. "/frontend/src/api/new_module.ts", ops[1].path)
    assert.are.equal("export function hello() { return 'hi'; }", ops[1].content)
  end)

  it("creates the file on disk with correct content via the executor", function()
    local root = make_tmp_dir()
    local response = "FILE:CREATE " .. root .. "/newfile.lua\n```lua\nreturn 42\n```"

    local ops = parse_response(response, root, nil)
    assert.are.equal(1, #ops)

    local ok = executor.create_file(ops[1].path, ops[1].content)
    assert.is_true(ok)
    vim.wait(30)

    assert.are.equal("return 42", read_file(root .. "/newfile.lua"))
  end)
end)

describe("parse_response — FILE:MODIFY with multiple SEARCH/REPLACE blocks", function()
  it("applies an import-line insertion block and a body-change block, in order", function()
    local root = make_tmp_dir()
    local target = root .. "/module.lua"
    write_file(target, table.concat({
      "local A = require('a')",
      "",
      "local function greet()",
      "  return 'hi'",
      "end",
    }, "\n"))

    local response = table.concat({
      "FILE:MODIFY " .. target,
      "<<<<<<< SEARCH",
      "local A = require('a')",
      "=======",
      "local A = require('a')",
      "local B = require('b')",
      ">>>>>>> REPLACE",
      "<<<<<<< SEARCH",
      "  return 'hi'",
      "=======",
      "  return 'hello, ' .. B.name",
      ">>>>>>> REPLACE",
    }, "\n")

    local ops, is_agent = parse_response(response, root, target)
    assert.is_true(is_agent)
    assert.are.equal(2, #ops)
    assert.are.equal("modify", ops[1].action)
    assert.are.equal("modify", ops[2].action)

    -- Apply both modify ops through the executor, in order.
    for _, op in ipairs(ops) do
      local ok = executor.modify_file(op.path, op.search, op.replace)
      assert.is_true(ok)
    end
    vim.wait(30)

    local final = read_file(target)
    assert.are.equal(table.concat({
      "local A = require('a')",
      "local B = require('b')",
      "",
      "local function greet()",
      "  return 'hello, ' .. B.name",
      "end",
    }, "\n"), final)
  end)
end)

describe("parse_response — truncated FILE:CREATE rejection", function()
  it("drops a FILE:CREATE whose fenced body is empty (truncated mid-stream response)", function()
    local root = make_tmp_dir()
    local response = table.concat({
      "FILE:CREATE " .. root .. "/truncated.lua",
      "```lua",
      "```",
    }, "\n")

    local ops, is_agent, _tool_calls, warnings = parse_response(response, root, nil)

    assert.are.equal(0, #ops)
    assert.is_table(warnings)
    assert.is_true(#warnings > 0)
  end)

  it("drops a FILE:CREATE whose fenced body is whitespace-only", function()
    local root = make_tmp_dir()
    local response = table.concat({
      "FILE:CREATE " .. root .. "/truncated_ws.lua",
      "```lua",
      "   ",
      "```",
    }, "\n")

    local ops, _is_agent, _tool_calls, warnings = parse_response(response, root, nil)

    assert.are.equal(0, #ops)
    assert.is_table(warnings)
    assert.is_true(#warnings > 0)
  end)

  it("still parses a non-empty FILE:CREATE body into one create op (regression guard)", function()
    local root = make_tmp_dir()
    local response = table.concat({
      "FILE:CREATE " .. root .. "/ok.lua",
      "```lua",
      "return 1",
      "```",
    }, "\n")

    local ops, is_agent, _tool_calls, warnings = parse_response(response, root, nil)

    assert.is_true(is_agent)
    assert.are.equal(1, #ops)
    assert.are.equal("return 1", ops[1].content)
    assert.is_table(warnings)
    assert.are.equal(0, #warnings)
  end)
end)

describe("parse_response — ambiguous path resolution", function()
  it("flags an unresolved/low-confidence path when no candidate base or target hint exists", function()
    local root = make_tmp_dir()
    -- No directory anywhere named after this segment, no target_path hint,
    -- and no existing file under any candidate base — this must NOT silently
    -- resolve as a confident cwd-joined guess.
    local response = table.concat({
      "FILE:CREATE zzz_no_such_dir_xyz/module.lua",
      "```lua",
      "return true",
      "```",
    }, "\n")

    local ops, _is_agent, _tool_calls, warnings = parse_response(response, root, nil)

    assert.are.equal(1, #ops)
    assert.is_table(warnings)
    assert.is_true(#warnings > 0)
  end)

  it("still resolves an unambiguous monorepo path unchanged (regression guard)", function()
    local root = make_tmp_dir()
    vim.fn.mkdir(root .. "/frontend/src/api", "p")
    local target_path = root .. "/frontend/src/api/existing.ts"
    write_file(target_path, "// existing file")

    local response = table.concat({
      "FILE:CREATE src/api/new_module.ts",
      "```typescript",
      "export function hello() { return 'hi'; }",
      "```",
    }, "\n")

    local ops, is_agent, _tool_calls, warnings = parse_response(response, root, target_path)

    assert.is_true(is_agent)
    assert.are.equal(1, #ops)
    assert.are.equal(root .. "/frontend/src/api/new_module.ts", ops[1].path)
    assert.is_table(warnings)
    assert.are.equal(0, #warnings)
  end)
end)

describe("parse_response — FILE:DELETE + dedup handling", function()
  it("dedupes repeated FILE:DELETE for the same path (last-wins) and keeps unrelated ops", function()
    local root = make_tmp_dir()
    local to_delete = root .. "/gone.lua"
    local to_create = root .. "/created.lua"
    write_file(to_delete, "-- will be deleted")

    local response = table.concat({
      "FILE:DELETE " .. to_delete,
      "FILE:DELETE " .. to_delete, -- model repeats itself
      "FILE:CREATE " .. to_create,
      "```lua",
      "return true",
      "```",
    }, "\n")

    local ops = parse_response(response, root, nil)
    assert.are.equal(3, #ops) -- parser doesn't dedupe; executor does

    local applied, failed, errors = executor.execute(ops)
    vim.wait(30)

    assert.are.equal(2, applied) -- 1 delete (deduped) + 1 create
    assert.are.equal(0, failed)
    assert.are.same({}, errors)

    assert.is_nil(read_file(to_delete))
    assert.are.equal("return true", read_file(to_create))
  end)
end)

describe("parse_response — tool marker boundary", function()
  it("rejects malformed, non-object, and double-encoded marker payloads", function()
    local response = table.concat({
      'TOOL:CODEGRAPH {"query":"safe"} {"query":"duplicate"}',
      "TOOL:CODEGRAPH {\"query\":",
      'TOOL:ASK_USER ["not-an-object"]',
      'TOOL:UNKNOWN {"command":"rm -rf /"}',
    }, "\n")

    local operations, is_agent, calls = parse_response(response, "/tmp/project", nil)

    assert.are.same({}, operations)
    assert.is_false(is_agent)
    assert.are.same({}, calls)
  end)

  it("preserves one valid canonical marker while ignoring an unknown shell marker", function()
    local response = table.concat({
      'TOOL:CODEGRAPH {"query":"safe"}',
      "TOOL:SHELL echo unsafe",
    }, "\n")

    local _operations, is_agent, calls = parse_response(response, "/tmp/project", nil)

    assert.is_true(is_agent)
    assert.are.equal(1, #calls)
    assert.are.equal("registry", calls[1].type)
    assert.are.equal("codegraph_context", calls[1].name)
    assert.are.same({ query = "safe" }, calls[1].args)
  end)
end)
