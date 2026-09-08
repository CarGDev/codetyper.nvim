--- Tests for the agent write-boundary guards in core/agent/executor.lua.
--- Confirmed data-loss vector: nil/empty content reaching create_file/modify_file
--- must never truncate or create a file on disk. Uses a real temp directory,
--- no LLM/network calls.

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

describe("executor.create_file — content guard", function()
  it("rejects nil content and does not create the file", function()
    local root = make_tmp_dir()
    local path = root .. "/never_created.lua"

    local ok, err = executor.create_file(path, nil)

    assert.is_false(ok)
    assert.is_string(err)
    assert.is_nil(read_file(path))
  end)

  it("rejects empty-string content and does not create the file", function()
    local root = make_tmp_dir()
    local path = root .. "/never_created_empty.lua"

    local ok, err = executor.create_file(path, "")

    assert.is_false(ok)
    assert.is_string(err)
    assert.is_nil(read_file(path))
  end)

  it("still creates the file when content is non-empty (regression guard)", function()
    local root = make_tmp_dir()
    local path = root .. "/created.lua"

    local ok = executor.create_file(path, "return 42")

    assert.is_true(ok)
    vim.wait(30)
    assert.are.equal("return 42", read_file(path))
  end)
end)

describe("executor.modify_file — write-back guard", function()
  it("rejects when the computed replacement collapses to empty, leaving the file unchanged", function()
    local root = make_tmp_dir()
    local path = root .. "/module.lua"
    write_file(path, "local a = 1\nlocal b = 2\n")

    -- readfile() drops the trailing newline, so the SEARCH text below must
    -- match the joined-without-trailing-newline content exactly for the
    -- gsub to succeed — this SEARCH matches the ENTIRE body, and REPLACE
    -- is empty, which would collapse new_content to "" and must be
    -- rejected by default (not silently written as an emptied file).
    local ok, err = executor.modify_file(path, "local a = 1\nlocal b = 2", "")

    assert.is_false(ok)
    assert.is_string(err)
    assert.are.equal("local a = 1\nlocal b = 2\n", read_file(path))
  end)

  it("still writes back a successful non-empty replace (regression guard)", function()
    local root = make_tmp_dir()
    local path = root .. "/module2.lua"
    write_file(path, "local a = 1\nlocal b = 2\n")

    local ok = executor.modify_file(path, "local a = 1", "local a = 99")

    assert.is_true(ok)
    vim.wait(30)
    -- readfile() drops the trailing newline when splitting into lines, so the
    -- re-joined content written back has no trailing "\n" either.
    assert.are.equal("local a = 99\nlocal b = 2", read_file(path))
  end)
end)
