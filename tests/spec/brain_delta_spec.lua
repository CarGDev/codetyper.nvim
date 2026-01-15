--- Tests for brain/delta modules
describe("brain.delta", function()
  local diff
  local commit
  local storage
  local types
  local test_root = "/tmp/codetyper_test_" .. os.time()

  before_each(function()
    -- Clear module cache
    package.loaded["codetyper.brain.delta.diff"] = nil
    package.loaded["codetyper.brain.delta.commit"] = nil
    package.loaded["codetyper.brain.storage"] = nil
    package.loaded["codetyper.brain.types"] = nil

    diff = require("codetyper.brain.delta.diff")
    commit = require("codetyper.brain.delta.commit")
    storage = require("codetyper.brain.storage")
    types = require("codetyper.brain.types")

    storage.clear_cache()
    vim.fn.mkdir(test_root, "p")
    storage.ensure_dirs(test_root)

    -- Mock get_project_root
    local utils = require("codetyper.utils")
    utils.get_project_root = function()
      return test_root
    end
  end)

  after_each(function()
    vim.fn.delete(test_root, "rf")
    storage.clear_cache()
  end)

  describe("diff.compute", function()
    it("detects added values", function()
      local diffs = diff.compute(nil, { a = 1 })

      assert.equals(1, #diffs)
      assert.equals("add", diffs[1].op)
    end)

    it("detects deleted values", function()
      local diffs = diff.compute({ a = 1 }, nil)

      assert.equals(1, #diffs)
      assert.equals("delete", diffs[1].op)
    end)

    it("detects replaced values", function()
      local diffs = diff.compute({ a = 1 }, { a = 2 })

      assert.equals(1, #diffs)
      assert.equals("replace", diffs[1].op)
      assert.equals(1, diffs[1].from)
      assert.equals(2, diffs[1].to)
    end)

    it("detects nested changes", function()
      local before = { a = { b = 1 } }
      local after = { a = { b = 2 } }

      local diffs = diff.compute(before, after)

      assert.equals(1, #diffs)
      assert.equals("a.b", diffs[1].path)
    end)

    it("returns empty for identical values", function()
      local diffs = diff.compute({ a = 1 }, { a = 1 })
      assert.equals(0, #diffs)
    end)
  end)

  describe("diff.apply", function()
    it("applies add operation", function()
      local base = { a = 1 }
      local diffs = { { op = "add", path = "b", value = 2 } }

      local result = diff.apply(base, diffs)

      assert.equals(2, result.b)
    end)

    it("applies replace operation", function()
      local base = { a = 1 }
      local diffs = { { op = "replace", path = "a", to = 2 } }

      local result = diff.apply(base, diffs)

      assert.equals(2, result.a)
    end)

    it("applies delete operation", function()
      local base = { a = 1, b = 2 }
      local diffs = { { op = "delete", path = "a" } }

      local result = diff.apply(base, diffs)

      assert.is_nil(result.a)
      assert.equals(2, result.b)
    end)

    it("applies nested changes", function()
      local base = { a = { b = 1 } }
      local diffs = { { op = "replace", path = "a.b", to = 2 } }

      local result = diff.apply(base, diffs)

      assert.equals(2, result.a.b)
    end)
  end)

  describe("diff.reverse", function()
    it("reverses add to delete", function()
      local diffs = { { op = "add", path = "a", value = 1 } }

      local reversed = diff.reverse(diffs)

      assert.equals("delete", reversed[1].op)
    end)

    it("reverses delete to add", function()
      local diffs = { { op = "delete", path = "a", value = 1 } }

      local reversed = diff.reverse(diffs)

      assert.equals("add", reversed[1].op)
    end)

    it("reverses replace", function()
      local diffs = { { op = "replace", path = "a", from = 1, to = 2 } }

      local reversed = diff.reverse(diffs)

      assert.equals("replace", reversed[1].op)
      assert.equals(2, reversed[1].from)
      assert.equals(1, reversed[1].to)
    end)
  end)

  describe("diff.equals", function()
    it("returns true for identical states", function()
      assert.is_true(diff.equals({ a = 1 }, { a = 1 }))
    end)

    it("returns false for different states", function()
      assert.is_false(diff.equals({ a = 1 }, { a = 2 }))
    end)
  end)

  describe("commit.create", function()
    it("creates a delta commit", function()
      local changes = {
        { op = "add", path = "test.node1", ah = "abc123" },
      }

      local delta = commit.create(changes, "Test commit", "test")

      assert.is_not_nil(delta)
      assert.is_not_nil(delta.h)
      assert.equals("Test commit", delta.m.msg)
      assert.equals(1, #delta.ch)
    end)

    it("updates HEAD", function()
      local changes = { { op = "add", path = "test.node1", ah = "abc123" } }

      local delta = commit.create(changes, "Test", "test")

      local head = storage.get_head(test_root)
      assert.equals(delta.h, head)
    end)

    it("links to parent", function()
      local changes1 = { { op = "add", path = "test.node1", ah = "abc123" } }
      local delta1 = commit.create(changes1, "First", "test")

      local changes2 = { { op = "add", path = "test.node2", ah = "def456" } }
      local delta2 = commit.create(changes2, "Second", "test")

      assert.equals(delta1.h, delta2.p)
    end)

    it("returns nil for empty changes", function()
      local delta = commit.create({}, "Empty")
      assert.is_nil(delta)
    end)
  end)

  describe("commit.get", function()
    it("retrieves created delta", function()
      local changes = { { op = "add", path = "test.node1", ah = "abc123" } }
      local created = commit.create(changes, "Test", "test")

      local retrieved = commit.get(created.h)

      assert.is_not_nil(retrieved)
      assert.equals(created.h, retrieved.h)
    end)

    it("returns nil for non-existent delta", function()
      local retrieved = commit.get("nonexistent")
      assert.is_nil(retrieved)
    end)
  end)

  describe("commit.get_history", function()
    it("returns delta chain", function()
      commit.create({ { op = "add", path = "node1", ah = "1" } }, "First", "test")
      commit.create({ { op = "add", path = "node2", ah = "2" } }, "Second", "test")
      commit.create({ { op = "add", path = "node3", ah = "3" } }, "Third", "test")

      local history = commit.get_history(10)

      assert.equals(3, #history)
      assert.equals("Third", history[1].m.msg)
      assert.equals("Second", history[2].m.msg)
      assert.equals("First", history[3].m.msg)
    end)

    it("respects limit", function()
      for i = 1, 5 do
        commit.create({ { op = "add", path = "node" .. i, ah = tostring(i) } }, "Commit " .. i, "test")
      end

      local history = commit.get_history(3)

      assert.equals(3, #history)
    end)
  end)

  describe("commit.summarize", function()
    it("summarizes delta statistics", function()
      local changes = {
        { op = "add", path = "nodes.a" },
        { op = "add", path = "nodes.b" },
        { op = "mod", path = "nodes.c" },
        { op = "del", path = "nodes.d" },
      }
      local delta = commit.create(changes, "Test", "test")

      local summary = commit.summarize(delta)

      assert.equals(2, summary.stats.adds)
      assert.equals(4, summary.stats.total)
      assert.is_true(vim.tbl_contains(summary.categories, "nodes"))
    end)
  end)
end)
