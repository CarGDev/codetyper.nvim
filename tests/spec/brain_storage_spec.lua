--- Tests for brain/storage.lua
describe("brain.storage", function()
  local storage
  local test_root = "/tmp/codetyper_test_" .. os.time()

  before_each(function()
    -- Clear module cache to get fresh state
    package.loaded["codetyper.brain.storage"] = nil
    package.loaded["codetyper.brain.types"] = nil
    storage = require("codetyper.brain.storage")

    -- Clear cache before each test
    storage.clear_cache()

    -- Create test directory
    vim.fn.mkdir(test_root, "p")
  end)

  after_each(function()
    -- Clean up test directory
    vim.fn.delete(test_root, "rf")
    storage.clear_cache()
  end)

  describe("get_brain_dir", function()
    it("returns correct path", function()
      local dir = storage.get_brain_dir(test_root)
      assert.equals(test_root .. "/.coder/brain", dir)
    end)
  end)

  describe("ensure_dirs", function()
    it("creates required directories", function()
      local result = storage.ensure_dirs(test_root)
      assert.is_true(result)

      -- Check directories exist
      assert.equals(1, vim.fn.isdirectory(test_root .. "/.coder/brain"))
      assert.equals(1, vim.fn.isdirectory(test_root .. "/.coder/brain/nodes"))
      assert.equals(1, vim.fn.isdirectory(test_root .. "/.coder/brain/indices"))
      assert.equals(1, vim.fn.isdirectory(test_root .. "/.coder/brain/deltas"))
      assert.equals(1, vim.fn.isdirectory(test_root .. "/.coder/brain/deltas/objects"))
    end)
  end)

  describe("get_path", function()
    it("returns correct path for simple key", function()
      local path = storage.get_path("meta", test_root)
      assert.equals(test_root .. "/.coder/brain/meta.json", path)
    end)

    it("returns correct path for nested key", function()
      local path = storage.get_path("nodes.patterns", test_root)
      assert.equals(test_root .. "/.coder/brain/nodes/patterns.json", path)
    end)

    it("returns correct path for deeply nested key", function()
      local path = storage.get_path("deltas.objects.abc123", test_root)
      assert.equals(test_root .. "/.coder/brain/deltas/objects/abc123.json", path)
    end)
  end)

  describe("save and load", function()
    it("saves and loads data correctly", function()
      storage.ensure_dirs(test_root)

      local data = { test = "value", count = 42 }
      storage.save("meta", data, test_root, true) -- immediate

      -- Clear cache and reload
      storage.clear_cache()
      local loaded = storage.load("meta", test_root)

      assert.equals("value", loaded.test)
      assert.equals(42, loaded.count)
    end)

    it("returns empty table for missing files", function()
      storage.ensure_dirs(test_root)

      local loaded = storage.load("nonexistent", test_root)
      assert.same({}, loaded)
    end)
  end)

  describe("get_meta", function()
    it("creates default meta if not exists", function()
      storage.ensure_dirs(test_root)

      local meta = storage.get_meta(test_root)

      assert.is_not_nil(meta.v)
      assert.equals(0, meta.nc)
      assert.equals(0, meta.ec)
      assert.equals(0, meta.dc)
    end)
  end)

  describe("update_meta", function()
    it("updates meta values", function()
      storage.ensure_dirs(test_root)

      storage.update_meta({ nc = 5 }, test_root)
      local meta = storage.get_meta(test_root)

      assert.equals(5, meta.nc)
    end)
  end)

  describe("get/save_nodes", function()
    it("saves and retrieves nodes by type", function()
      storage.ensure_dirs(test_root)

      local nodes = {
        ["n_pat_123_abc"] = { id = "n_pat_123_abc", t = "pat" },
        ["n_pat_456_def"] = { id = "n_pat_456_def", t = "pat" },
      }

      storage.save_nodes("patterns", nodes, test_root)
      storage.flush("nodes.patterns", test_root)

      storage.clear_cache()
      local loaded = storage.get_nodes("patterns", test_root)

      assert.equals(2, vim.tbl_count(loaded))
      assert.equals("n_pat_123_abc", loaded["n_pat_123_abc"].id)
    end)
  end)

  describe("get/save_graph", function()
    it("saves and retrieves graph", function()
      storage.ensure_dirs(test_root)

      local graph = {
        adj = { node1 = { sem = { "node2" } } },
        radj = { node2 = { sem = { "node1" } } },
      }

      storage.save_graph(graph, test_root)
      storage.flush("graph", test_root)

      storage.clear_cache()
      local loaded = storage.get_graph(test_root)

      assert.same({ "node2" }, loaded.adj.node1.sem)
    end)
  end)

  describe("get/set_head", function()
    it("stores and retrieves HEAD", function()
      storage.ensure_dirs(test_root)

      storage.set_head("abc12345", test_root)
      storage.flush("meta", test_root) -- Ensure written to disk

      storage.clear_cache()
      local head = storage.get_head(test_root)

      assert.equals("abc12345", head)
    end)
  end)

  describe("exists", function()
    it("returns false for non-existent brain", function()
      assert.is_false(storage.exists(test_root))
    end)

    it("returns true after ensure_dirs", function()
      storage.ensure_dirs(test_root)
      assert.is_true(storage.exists(test_root))
    end)
  end)
end)
