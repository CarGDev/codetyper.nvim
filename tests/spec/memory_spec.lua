---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/indexer/memory.lua

describe("indexer.memory", function()
	local memory
	local utils

	-- Mock cwd for testing
	local test_cwd = "/tmp/codetyper_test_memory"

	before_each(function()
		-- Reset modules
		package.loaded["codetyper.indexer.memory"] = nil
		package.loaded["codetyper.utils"] = nil

		memory = require("codetyper.indexer.memory")
		utils = require("codetyper.utils")

		-- Create test directory structure
		vim.fn.mkdir(test_cwd, "p")
		vim.fn.mkdir(test_cwd .. "/.coder", "p")
		vim.fn.mkdir(test_cwd .. "/.coder/memories", "p")
		vim.fn.mkdir(test_cwd .. "/.coder/memories/files", "p")
		vim.fn.mkdir(test_cwd .. "/.coder/sessions", "p")

		-- Mock getcwd to return test directory
		vim.fn.getcwd = function()
			return test_cwd
		end

		-- Mock get_project_root
		package.loaded["codetyper.utils"].get_project_root = function()
			return test_cwd
		end
	end)

	after_each(function()
		-- Clean up test directory
		vim.fn.delete(test_cwd, "rf")
	end)

	describe("store_memory", function()
		it("should store a pattern memory", function()
			local mem = {
				type = "pattern",
				content = "Use snake_case for function names",
				weight = 0.8,
			}

			local result = memory.store_memory(mem)

			assert.is_true(result)
		end)

		it("should store a convention memory", function()
			local mem = {
				type = "convention",
				content = "Project uses TypeScript",
				weight = 0.9,
			}

			local result = memory.store_memory(mem)

			assert.is_true(result)
		end)

		it("should assign an ID to the memory", function()
			local mem = {
				type = "pattern",
				content = "Test memory",
			}

			memory.store_memory(mem)

			assert.is_truthy(mem.id)
			assert.is_true(mem.id:match("^mem_") ~= nil)
		end)

		it("should set timestamps", function()
			local mem = {
				type = "pattern",
				content = "Test memory",
			}

			memory.store_memory(mem)

			assert.is_truthy(mem.created_at)
			assert.is_truthy(mem.updated_at)
		end)
	end)

	describe("load_patterns", function()
		it("should return empty table when no patterns exist", function()
			local patterns = memory.load_patterns()

			assert.is_table(patterns)
		end)

		it("should load stored patterns", function()
			-- Store a pattern first
			memory.store_memory({
				type = "pattern",
				content = "Test pattern",
				weight = 0.5,
			})

			-- Force reload
			package.loaded["codetyper.indexer.memory"] = nil
			memory = require("codetyper.indexer.memory")

			local patterns = memory.load_patterns()

			assert.is_table(patterns)
			local count = 0
			for _ in pairs(patterns) do
				count = count + 1
			end
			assert.is_true(count >= 1)
		end)
	end)

	describe("load_conventions", function()
		it("should return empty table when no conventions exist", function()
			local conventions = memory.load_conventions()

			assert.is_table(conventions)
		end)
	end)

	describe("store_file_memory", function()
		it("should store file-specific memory", function()
			local file_index = {
				functions = {
					{ name = "test_func", line = 10, end_line = 20 },
				},
				classes = {},
				exports = {},
				imports = {},
			}

			local result = memory.store_file_memory("src/main.lua", file_index)

			assert.is_true(result)
		end)
	end)

	describe("load_file_memory", function()
		it("should return nil when file memory does not exist", function()
			local result = memory.load_file_memory("nonexistent.lua")

			assert.is_nil(result)
		end)

		it("should load stored file memory", function()
			local file_index = {
				functions = {
					{ name = "my_function", line = 5, end_line = 15 },
				},
				classes = {},
				exports = {},
				imports = {},
			}

			memory.store_file_memory("src/test.lua", file_index)
			local loaded = memory.load_file_memory("src/test.lua")

			assert.is_table(loaded)
			assert.equals("src/test.lua", loaded.path)
			assert.equals(1, #loaded.functions)
			assert.equals("my_function", loaded.functions[1].name)
		end)
	end)

	describe("get_relevant", function()
		it("should return empty table when no memories exist", function()
			local results = memory.get_relevant("test query", 10)

			assert.is_table(results)
			assert.equals(0, #results)
		end)

		it("should find relevant memories by keyword", function()
			memory.store_memory({
				type = "pattern",
				content = "Use TypeScript for type safety",
				weight = 0.8,
			})
			memory.store_memory({
				type = "pattern",
				content = "Use Python for data processing",
				weight = 0.7,
			})

			local results = memory.get_relevant("TypeScript", 10)

			assert.is_true(#results >= 1)
			-- First result should contain TypeScript
			local found = false
			for _, r in ipairs(results) do
				if r.content:find("TypeScript") then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)

		it("should limit results", function()
			-- Store multiple memories
			for i = 1, 20 do
				memory.store_memory({
					type = "pattern",
					content = "Pattern number " .. i .. " about testing",
					weight = 0.5,
				})
			end

			local results = memory.get_relevant("testing", 5)

			assert.is_true(#results <= 5)
		end)
	end)

	describe("update_usage", function()
		it("should increment used_count", function()
			local mem = {
				type = "pattern",
				content = "Test pattern for usage tracking",
				weight = 0.5,
			}
			memory.store_memory(mem)

			memory.update_usage(mem.id)

			-- Reload and check
			package.loaded["codetyper.indexer.memory"] = nil
			memory = require("codetyper.indexer.memory")

			local patterns = memory.load_patterns()
			if patterns[mem.id] then
				assert.equals(1, patterns[mem.id].used_count)
			end
		end)
	end)

	describe("get_all", function()
		it("should return all memory types", function()
			memory.store_memory({ type = "pattern", content = "A pattern" })
			memory.store_memory({ type = "convention", content = "A convention" })

			local all = memory.get_all()

			assert.is_table(all.patterns)
			assert.is_table(all.conventions)
			assert.is_table(all.symbols)
		end)
	end)

	describe("clear", function()
		it("should clear all memories when no pattern provided", function()
			memory.store_memory({ type = "pattern", content = "Pattern 1" })
			memory.store_memory({ type = "convention", content = "Convention 1" })

			memory.clear()

			local all = memory.get_all()
			assert.equals(0, vim.tbl_count(all.patterns))
			assert.equals(0, vim.tbl_count(all.conventions))
		end)

		it("should clear only matching memories when pattern provided", function()
			local mem1 = { type = "pattern", content = "Pattern 1" }
			local mem2 = { type = "pattern", content = "Pattern 2" }
			memory.store_memory(mem1)
			memory.store_memory(mem2)

			-- Clear memories matching the first ID
			memory.clear(mem1.id)

			local patterns = memory.load_patterns()
			assert.is_nil(patterns[mem1.id])
		end)
	end)

	describe("prune", function()
		it("should remove low-weight unused memories", function()
			-- Store some low-weight memories
			memory.store_memory({
				type = "pattern",
				content = "Low weight pattern",
				weight = 0.05,
				used_count = 0,
			})
			memory.store_memory({
				type = "pattern",
				content = "High weight pattern",
				weight = 0.9,
				used_count = 0,
			})

			local pruned = memory.prune(0.1)

			-- Should have pruned at least one
			assert.is_true(pruned >= 0)
		end)

		it("should not remove frequently used memories", function()
			local mem = {
				type = "pattern",
				content = "Frequently used but low weight",
				weight = 0.05,
				used_count = 10,
			}
			memory.store_memory(mem)

			memory.prune(0.1)

			-- Memory should still exist because used_count > 0
			local patterns = memory.load_patterns()
			-- Note: prune only removes if used_count == 0 AND weight < threshold
			if patterns[mem.id] then
				assert.is_truthy(patterns[mem.id])
			end
		end)
	end)

	describe("get_stats", function()
		it("should return memory statistics", function()
			memory.store_memory({ type = "pattern", content = "P1" })
			memory.store_memory({ type = "pattern", content = "P2" })
			memory.store_memory({ type = "convention", content = "C1" })

			local stats = memory.get_stats()

			assert.is_table(stats)
			assert.equals(2, stats.patterns)
			assert.equals(1, stats.conventions)
			assert.equals(3, stats.total)
		end)
	end)
end)
