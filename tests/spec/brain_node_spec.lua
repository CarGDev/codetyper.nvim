--- Tests for brain/graph/node.lua
describe("brain.graph.node", function()
  local node
  local storage
  local types
  local test_root = "/tmp/codetyper_test_" .. os.time()

  before_each(function()
    -- Clear module cache
    package.loaded["codetyper.brain.graph.node"] = nil
    package.loaded["codetyper.brain.storage"] = nil
    package.loaded["codetyper.brain.types"] = nil
    package.loaded["codetyper.brain.hash"] = nil

    storage = require("codetyper.brain.storage")
    types = require("codetyper.brain.types")
    node = require("codetyper.brain.graph.node")

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
    node.pending = {}
  end)

  describe("create", function()
    it("creates a new node with correct structure", function()
      local created = node.create(types.NODE_TYPES.PATTERN, {
        s = "Test pattern summary",
        d = "Test pattern detail",
      }, {
        f = "test.lua",
      })

      assert.is_not_nil(created.id)
      assert.equals(types.NODE_TYPES.PATTERN, created.t)
      assert.equals("Test pattern summary", created.c.s)
      assert.equals("test.lua", created.ctx.f)
      assert.equals(0.5, created.sc.w)
      assert.equals(0, created.sc.u)
    end)

    it("generates unique IDs", function()
      local node1 = node.create(types.NODE_TYPES.PATTERN, { s = "First" }, {})
      local node2 = node.create(types.NODE_TYPES.PATTERN, { s = "Second" }, {})

      assert.is_not_nil(node1.id)
      assert.is_not_nil(node2.id)
      assert.not_equals(node1.id, node2.id)
    end)

    it("updates meta node count", function()
      local meta_before = storage.get_meta(test_root)
      local count_before = meta_before.nc

      node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      local meta_after = storage.get_meta(test_root)
      assert.equals(count_before + 1, meta_after.nc)
    end)

    it("tracks pending change", function()
      node.pending = {}
      node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      assert.equals(1, #node.pending)
      assert.equals("add", node.pending[1].op)
    end)
  end)

  describe("get", function()
    it("retrieves created node", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      local retrieved = node.get(created.id)

      assert.is_not_nil(retrieved)
      assert.equals(created.id, retrieved.id)
      assert.equals("Test", retrieved.c.s)
    end)

    it("returns nil for non-existent node", function()
      local retrieved = node.get("n_pat_0_nonexistent")
      assert.is_nil(retrieved)
    end)
  end)

  describe("update", function()
    it("updates node content", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Original" }, {})

      node.update(created.id, { c = { s = "Updated" } })

      local updated = node.get(created.id)
      assert.equals("Updated", updated.c.s)
    end)

    it("updates node scores", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      node.update(created.id, { sc = { w = 0.9 } })

      local updated = node.get(created.id)
      assert.equals(0.9, updated.sc.w)
    end)

    it("increments version", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})
      local original_version = created.m.v

      node.update(created.id, { c = { s = "Updated" } })

      local updated = node.get(created.id)
      assert.equals(original_version + 1, updated.m.v)
    end)

    it("returns nil for non-existent node", function()
      local result = node.update("n_pat_0_nonexistent", { c = { s = "Test" } })
      assert.is_nil(result)
    end)
  end)

  describe("delete", function()
    it("removes node", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      local result = node.delete(created.id)

      assert.is_true(result)
      assert.is_nil(node.get(created.id))
    end)

    it("decrements meta node count", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})
      local meta_before = storage.get_meta(test_root)
      local count_before = meta_before.nc

      node.delete(created.id)

      local meta_after = storage.get_meta(test_root)
      assert.equals(count_before - 1, meta_after.nc)
    end)

    it("returns false for non-existent node", function()
      local result = node.delete("n_pat_0_nonexistent")
      assert.is_false(result)
    end)
  end)

  describe("find", function()
    it("finds nodes by type", function()
      node.create(types.NODE_TYPES.PATTERN, { s = "Pattern 1" }, {})
      node.create(types.NODE_TYPES.PATTERN, { s = "Pattern 2" }, {})
      node.create(types.NODE_TYPES.CORRECTION, { s = "Correction 1" }, {})

      local patterns = node.find({ types = { types.NODE_TYPES.PATTERN } })

      assert.equals(2, #patterns)
    end)

    it("finds nodes by file", function()
      node.create(types.NODE_TYPES.PATTERN, { s = "Test 1" }, { f = "file1.lua" })
      node.create(types.NODE_TYPES.PATTERN, { s = "Test 2" }, { f = "file2.lua" })
      node.create(types.NODE_TYPES.PATTERN, { s = "Test 3" }, { f = "file1.lua" })

      local found = node.find({ file = "file1.lua" })

      assert.equals(2, #found)
    end)

    it("finds nodes by query", function()
      node.create(types.NODE_TYPES.PATTERN, { s = "Foo bar baz" }, {})
      node.create(types.NODE_TYPES.PATTERN, { s = "Something else" }, {})

      local found = node.find({ query = "foo" })

      assert.equals(1, #found)
      assert.equals("Foo bar baz", found[1].c.s)
    end)

    it("respects limit", function()
      for i = 1, 10 do
        node.create(types.NODE_TYPES.PATTERN, { s = "Node " .. i }, {})
      end

      local found = node.find({ limit = 5 })

      assert.equals(5, #found)
    end)
  end)

  describe("record_usage", function()
    it("increments usage count", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      node.record_usage(created.id, true)

      local updated = node.get(created.id)
      assert.equals(1, updated.sc.u)
    end)

    it("updates success rate", function()
      local created = node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      node.record_usage(created.id, true)
      node.record_usage(created.id, false)

      local updated = node.get(created.id)
      assert.equals(0.5, updated.sc.sr)
    end)
  end)

  describe("get_and_clear_pending", function()
    it("returns and clears pending changes", function()
      node.pending = {}
      node.create(types.NODE_TYPES.PATTERN, { s = "Test" }, {})

      local pending = node.get_and_clear_pending()

      assert.equals(1, #pending)
      assert.equals(0, #node.pending)
    end)
  end)
end)
