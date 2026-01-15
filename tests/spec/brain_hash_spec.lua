--- Tests for brain/hash.lua
describe("brain.hash", function()
  local hash

  before_each(function()
    package.loaded["codetyper.brain.hash"] = nil
    hash = require("codetyper.brain.hash")
  end)

  describe("compute", function()
    it("returns 8-character hash", function()
      local result = hash.compute("test string")
      assert.equals(8, #result)
    end)

    it("returns consistent hash for same input", function()
      local result1 = hash.compute("test")
      local result2 = hash.compute("test")
      assert.equals(result1, result2)
    end)

    it("returns different hash for different input", function()
      local result1 = hash.compute("test1")
      local result2 = hash.compute("test2")
      assert.not_equals(result1, result2)
    end)

    it("handles empty string", function()
      local result = hash.compute("")
      assert.equals("00000000", result)
    end)

    it("handles nil", function()
      local result = hash.compute(nil)
      assert.equals("00000000", result)
    end)
  end)

  describe("compute_table", function()
    it("hashes table as JSON", function()
      local result = hash.compute_table({ a = 1, b = 2 })
      assert.equals(8, #result)
    end)

    it("returns consistent hash for same table", function()
      local result1 = hash.compute_table({ x = "y" })
      local result2 = hash.compute_table({ x = "y" })
      assert.equals(result1, result2)
    end)
  end)

  describe("node_id", function()
    it("generates ID with correct format", function()
      local id = hash.node_id("pat", "test content")
      assert.truthy(id:match("^n_pat_%d+_%w+$"))
    end)

    it("generates unique IDs", function()
      local id1 = hash.node_id("pat", "test1")
      local id2 = hash.node_id("pat", "test2")
      assert.not_equals(id1, id2)
    end)
  end)

  describe("edge_id", function()
    it("generates ID with correct format", function()
      local id = hash.edge_id("source_node", "target_node")
      assert.truthy(id:match("^e_%w+_%w+$"))
    end)

    it("returns same ID for same source/target", function()
      local id1 = hash.edge_id("s1", "t1")
      local id2 = hash.edge_id("s1", "t1")
      assert.equals(id1, id2)
    end)
  end)

  describe("delta_hash", function()
    it("generates 8-character hash", function()
      local changes = { { op = "add", path = "test" } }
      local result = hash.delta_hash(changes, "parent", 12345)
      assert.equals(8, #result)
    end)

    it("includes parent in hash", function()
      local changes = { { op = "add", path = "test" } }
      local result1 = hash.delta_hash(changes, "parent1", 12345)
      local result2 = hash.delta_hash(changes, "parent2", 12345)
      assert.not_equals(result1, result2)
    end)
  end)

  describe("path_hash", function()
    it("returns 8-character hash", function()
      local result = hash.path_hash("/path/to/file.lua")
      assert.equals(8, #result)
    end)
  end)

  describe("matches", function()
    it("returns true for matching hashes", function()
      assert.is_true(hash.matches("abc12345", "abc12345"))
    end)

    it("returns false for different hashes", function()
      assert.is_false(hash.matches("abc12345", "def67890"))
    end)
  end)

  describe("random", function()
    it("returns 8-character string", function()
      local result = hash.random()
      assert.equals(8, #result)
    end)

    it("generates different values", function()
      local result1 = hash.random()
      local result2 = hash.random()
      -- Note: There's a tiny chance these could match, but very unlikely
      assert.not_equals(result1, result2)
    end)

    it("contains only hex characters", function()
      local result = hash.random()
      assert.truthy(result:match("^[0-9a-f]+$"))
    end)
  end)
end)
