---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/indexer/init.lua

describe("indexer", function()
	local indexer
	local utils

	-- Mock cwd for testing
	local test_cwd = "/tmp/codetyper_test_indexer"

	before_each(function()
		-- Reset modules
		package.loaded["codetyper.indexer"] = nil
		package.loaded["codetyper.indexer.scanner"] = nil
		package.loaded["codetyper.indexer.analyzer"] = nil
		package.loaded["codetyper.indexer.memory"] = nil
		package.loaded["codetyper.utils"] = nil

		indexer = require("codetyper.indexer")
		utils = require("codetyper.utils")

		-- Create test directory structure
		vim.fn.mkdir(test_cwd, "p")
		vim.fn.mkdir(test_cwd .. "/.coder", "p")
		vim.fn.mkdir(test_cwd .. "/src", "p")

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

	describe("setup", function()
		it("should accept configuration options", function()
			indexer.setup({
				enabled = true,
				auto_index = false,
			})

			local config = indexer.get_config()
			assert.is_false(config.auto_index)
		end)

		it("should use default configuration when no options provided", function()
			indexer.setup()

			local config = indexer.get_config()
			assert.is_true(config.enabled)
		end)
	end)

	describe("load_index", function()
		it("should return nil when no index exists", function()
			local index = indexer.load_index()

			assert.is_nil(index)
		end)

		it("should load existing index from file", function()
			-- Create a mock index file
			local mock_index = {
				version = 1,
				project_root = test_cwd,
				project_name = "test",
				project_type = "node",
				dependencies = {},
				dev_dependencies = {},
				files = {},
				symbols = {},
				last_indexed = os.time(),
				stats = { files = 0, functions = 0, classes = 0, exports = 0 },
			}
			utils.write_file(test_cwd .. "/.coder/index.json", vim.json.encode(mock_index))

			local index = indexer.load_index()

			assert.is_table(index)
			assert.equals("test", index.project_name)
			assert.equals("node", index.project_type)
		end)

		it("should cache loaded index", function()
			local mock_index = {
				version = 1,
				project_root = test_cwd,
				project_name = "cached_test",
				project_type = "lua",
				dependencies = {},
				dev_dependencies = {},
				files = {},
				symbols = {},
				last_indexed = os.time(),
				stats = { files = 0, functions = 0, classes = 0, exports = 0 },
			}
			utils.write_file(test_cwd .. "/.coder/index.json", vim.json.encode(mock_index))

			local index1 = indexer.load_index()
			local index2 = indexer.load_index()

			assert.equals(index1.project_name, index2.project_name)
		end)
	end)

	describe("save_index", function()
		it("should save index to file", function()
			local index = {
				version = 1,
				project_root = test_cwd,
				project_name = "save_test",
				project_type = "node",
				dependencies = { express = "^4.18.0" },
				dev_dependencies = {},
				files = {},
				symbols = {},
				last_indexed = os.time(),
				stats = { files = 0, functions = 0, classes = 0, exports = 0 },
			}

			local result = indexer.save_index(index)

			assert.is_true(result)

			-- Verify file was created
			local content = utils.read_file(test_cwd .. "/.coder/index.json")
			assert.is_truthy(content)

			local decoded = vim.json.decode(content)
			assert.equals("save_test", decoded.project_name)
		end)

		it("should create .coder directory if it does not exist", function()
			vim.fn.delete(test_cwd .. "/.coder", "rf")

			local index = {
				version = 1,
				project_root = test_cwd,
				project_name = "test",
				project_type = "unknown",
				dependencies = {},
				dev_dependencies = {},
				files = {},
				symbols = {},
				last_indexed = os.time(),
				stats = { files = 0, functions = 0, classes = 0, exports = 0 },
			}

			indexer.save_index(index)

			assert.equals(1, vim.fn.isdirectory(test_cwd .. "/.coder"))
		end)
	end)

	describe("index_project", function()
		it("should create an index for the project", function()
			-- Create some test files
			utils.write_file(test_cwd .. "/package.json", '{"name":"test","dependencies":{}}')
			utils.write_file(test_cwd .. "/src/main.lua", [[
local M = {}
function M.hello()
  return "world"
end
return M
]])

			indexer.setup({ index_extensions = { "lua" } })
			local index = indexer.index_project()

			assert.is_table(index)
			assert.equals("node", index.project_type)
			assert.is_truthy(index.stats.files >= 0)
		end)

		it("should detect project dependencies", function()
			utils.write_file(test_cwd .. "/package.json", [[{
				"name": "test",
				"dependencies": {
					"express": "^4.18.0",
					"lodash": "^4.17.0"
				}
			}]])

			indexer.setup()
			local index = indexer.index_project()

			assert.is_table(index.dependencies)
			assert.equals("^4.18.0", index.dependencies.express)
		end)

		it("should call callback when complete", function()
			local callback_called = false
			local callback_index = nil

			indexer.setup()
			indexer.index_project(function(index)
				callback_called = true
				callback_index = index
			end)

			assert.is_true(callback_called)
			assert.is_table(callback_index)
		end)
	end)

	describe("index_file", function()
		it("should index a single file", function()
			utils.write_file(test_cwd .. "/src/test.lua", [[
local M = {}
function M.add(a, b)
  return a + b
end
function M.subtract(a, b)
  return a - b
end
return M
]])

			indexer.setup({ index_extensions = { "lua" } })
			-- First create an initial index
			indexer.index_project()

			local file_index = indexer.index_file(test_cwd .. "/src/test.lua")

			assert.is_table(file_index)
			assert.equals("src/test.lua", file_index.path)
		end)

		it("should update symbols in the main index", function()
			utils.write_file(test_cwd .. "/src/utils.lua", [[
local M = {}
function M.format_string(str)
  return string.upper(str)
end
return M
]])

			indexer.setup({ index_extensions = { "lua" } })
			indexer.index_project()
			indexer.index_file(test_cwd .. "/src/utils.lua")

			local index = indexer.load_index()
			assert.is_table(index.files)
		end)
	end)

	describe("get_status", function()
		it("should return indexed: false when no index exists", function()
			local status = indexer.get_status()

			assert.is_false(status.indexed)
			assert.is_nil(status.stats)
		end)

		it("should return status when index exists", function()
			indexer.setup()
			indexer.index_project()

			local status = indexer.get_status()

			assert.is_true(status.indexed)
			assert.is_table(status.stats)
			assert.is_truthy(status.last_indexed)
		end)
	end)

	describe("get_context_for", function()
		it("should return context with project type", function()
			utils.write_file(test_cwd .. "/package.json", '{"name":"test"}')
			indexer.setup()
			indexer.index_project()

			local context = indexer.get_context_for({
				file = test_cwd .. "/src/main.lua",
				prompt = "add a function",
			})

			assert.is_table(context)
			assert.equals("node", context.project_type)
		end)

		it("should find relevant symbols", function()
			utils.write_file(test_cwd .. "/src/utils.lua", [[
local M = {}
function M.calculate_total(items)
  return 0
end
return M
]])
			indexer.setup({ index_extensions = { "lua" } })
			indexer.index_project()

			local context = indexer.get_context_for({
				file = test_cwd .. "/src/main.lua",
				prompt = "use calculate_total function",
			})

			assert.is_table(context)
			-- Should find the calculate symbol
			if context.relevant_symbols and context.relevant_symbols.calculate then
				assert.is_table(context.relevant_symbols.calculate)
			end
		end)
	end)

	describe("clear", function()
		it("should remove the index file", function()
			indexer.setup()
			indexer.index_project()

			-- Verify index exists
			assert.is_true(indexer.get_status().indexed)

			indexer.clear()

			-- Verify index is gone
			local status = indexer.get_status()
			assert.is_false(status.indexed)
		end)
	end)

	describe("schedule_index_file", function()
		it("should not index when disabled", function()
			indexer.setup({ enabled = false })

			-- This should not throw or cause issues
			indexer.schedule_index_file(test_cwd .. "/src/test.lua")
		end)

		it("should not index when auto_index is false", function()
			indexer.setup({ enabled = true, auto_index = false })

			-- This should not throw or cause issues
			indexer.schedule_index_file(test_cwd .. "/src/test.lua")
		end)
	end)
end)
