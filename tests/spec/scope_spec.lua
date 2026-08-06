--- Tests for scope resolution (heuristic, no Tree-sitter dependency required).
--- Covers: "insert/replace a function at the correct line" by verifying scope
--- detection brackets the whole function, then feeding that range into patch
--- creation.

local scope = require("codetyper.core.scope")
local patch = require("codetyper.core.diff.patch")

local function make_lua_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "lua"
  return bufnr
end

describe("scope.resolve_scope_heuristic", function()
  it("brackets the whole enclosing function for a cursor inside it", function()
    local bufnr = make_lua_buffer({
      "local function outer()",
      "  local x = 1",
      "  local y = 2",
      "  return x + y",
      "end",
      "",
      "local function other() end",
    })

    -- Cursor on line 3 ("local y = 2"), inside `outer`
    local result = scope.resolve_scope_heuristic(bufnr, 3, 1)

    assert.is_not_nil(result)
    assert.are.equal("function", result.type)
    assert.are.equal(1, result.range.start_row)
    assert.are.equal(5, result.range.end_row)
    assert.are.equal("outer", result.name)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("computes injection_range matching the full function scope when replacing", function()
    local bufnr = make_lua_buffer({
      "local function target()",
      "  return 1",
      "end",
    })

    local found = scope.resolve_scope_heuristic(bufnr, 2, 1)
    assert.is_not_nil(found)

    local path = "/tmp/codetyper_test_scope_" .. os.time() .. ".lua"
    vim.api.nvim_buf_set_name(bufnr, path)

    local event = {
      id = "evt_scope",
      bufnr = bufnr,
      target_path = path,
      intent = { action = "replace" },
      range = { start_line = found.range.start_row, end_line = found.range.end_row },
      scope_range = { start_line = found.range.start_row, end_line = found.range.end_row },
    }

    local p = patch.create_from_event(event, "local function target()\n  return 2\nend", 0.9)

    assert.are.equal("replace", p.injection_strategy)
    assert.is_not_nil(p.injection_range)
    assert.are.equal(found.range.start_row, p.injection_range.start_line)
    assert.are.equal(found.range.end_row, p.injection_range.end_line)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns nil for unsupported filetypes", function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "some random text" })
    vim.bo[bufnr].filetype = "totally_unknown_ft"

    local result = scope.resolve_scope_heuristic(bufnr, 1, 1)
    assert.is_nil(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
