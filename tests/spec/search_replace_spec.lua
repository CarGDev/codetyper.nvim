--- Tests for SEARCH/REPLACE parsing and application (pure functions, no LLM/network).
--- Covers: "delete only one specific line" and "inject code in the middle of a file".

local search_replace = require("codetyper.core.diff.search_replace")

describe("search_replace.apply_block", function()
  it("deletes only the targeted line, leaving all others untouched", function()
    local content = table.concat({
      "line 1",
      "line 2 -- DELETE ME",
      "line 3",
      "line 4",
    }, "\n")

    local block = { search = "line 2 -- DELETE ME\n", replace = "" }
    local new_content, match, err = search_replace.apply_block(content, block)

    assert.is_nil(err)
    assert.is_not_nil(match)

    local lines = vim.split(new_content, "\n", { plain = true })
    assert.are.same({ "line 1", "line 3", "line 4" }, lines)
  end)

  it("injects new code exactly between the correct neighboring lines (mid-file)", function()
    local content = table.concat({
      "function first() end",
      "-- ANCHOR",
      "function last() end",
    }, "\n")

    local block = {
      search = "-- ANCHOR",
      replace = "-- ANCHOR\nfunction middle()\n  return 42\nend",
    }
    local new_content = search_replace.apply_block(content, block)
    local lines = vim.split(new_content, "\n", { plain = true })

    assert.are.same({
      "function first() end",
      "-- ANCHOR",
      "function middle()",
      "  return 42",
      "end",
      "function last() end",
    }, lines)
  end)

  it("returns an error when the search text cannot be found", function()
    local content = "local x = 1"
    local block = { search = "this text does not exist anywhere", replace = "y" }
    local new_content, match, err = search_replace.apply_block(content, block)

    assert.is_nil(new_content)
    assert.is_nil(match)
    assert.is_not_nil(err)
  end)
end)

describe("search_replace.apply_blocks (multi-block, e.g. import + body change)", function()
  it("applies multiple blocks in order, including an import-line insertion", function()
    local content = table.concat({
      "local A = require('a')",
      "",
      "local function greet()",
      "  return 'hi'",
      "end",
    }, "\n")

    local blocks = {
      -- Block 1: insert a new import above the existing one
      { search = "local A = require('a')", replace = "local A = require('a')\nlocal B = require('b')" },
      -- Block 2: change the function body
      { search = "  return 'hi'", replace = "  return 'hello, ' .. B.name" },
    }

    local new_content, results = search_replace.apply_blocks(content, blocks)

    assert.is_true(results[1].success)
    assert.is_true(results[2].success)

    local lines = vim.split(new_content, "\n", { plain = true })
    assert.are.same({
      "local A = require('a')",
      "local B = require('b')",
      "",
      "local function greet()",
      "  return 'hello, ' .. B.name",
      "end",
    }, lines)
  end)
end)

describe("search_replace.parse_blocks", function()
  it("parses claude-style <<<<<<< SEARCH blocks", function()
    local response = table.concat({
      "<<<<<<< SEARCH",
      "old code",
      "=======",
      "new code",
      ">>>>>>> REPLACE",
    }, "\n")

    local blocks = search_replace.parse_blocks(response)
    assert.are.equal(1, #blocks)
    assert.are.equal("old code", blocks[1].search)
    assert.are.equal("new code", blocks[1].replace)
  end)

  it("returns an empty list when no blocks are present", function()
    local blocks = search_replace.parse_blocks("just plain text, no markers")
    assert.are.equal(0, #blocks)
  end)
end)
