---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/indexer/scanner.lua

describe("indexer.scanner", function()
	local scanner
	local utils

	-- Mock cwd for testing
	local test_cwd = "/tmp/codetyper_test_scanner"

	before_each(function()
		-- Reset modules
		package.loaded["codetyper.indexer.scanner"] = nil
		package.loaded["codetyper.utils"] = nil

		scanner = require("codetyper.indexer.scanner")
		utils = require("codetyper.utils")

		-- Create test directory
		vim.fn.mkdir(test_cwd, "p")

		-- Mock getcwd to return test directory
		vim.fn.getcwd = function()
			return test_cwd
		end
	end)

	after_each(function()
		-- Clean up test directory
		vim.fn.delete(test_cwd, "rf")
	end)

	describe("detect_project_type", function()
		it("should detect node project from package.json", function()
			utils.write_file(test_cwd .. "/package.json", '{"name":"test"}')

			local project_type = scanner.detect_project_type(test_cwd)

			assert.equals("node", project_type)
		end)

		it("should detect rust project from Cargo.toml", function()
			utils.write_file(test_cwd .. "/Cargo.toml", '[package]\nname = "test"')

			local project_type = scanner.detect_project_type(test_cwd)

			assert.equals("rust", project_type)
		end)

		it("should detect go project from go.mod", function()
			utils.write_file(test_cwd .. "/go.mod", "module example.com/test")

			local project_type = scanner.detect_project_type(test_cwd)

			assert.equals("go", project_type)
		end)

		it("should detect python project from pyproject.toml", function()
			utils.write_file(test_cwd .. "/pyproject.toml", '[project]\nname = "test"')

			local project_type = scanner.detect_project_type(test_cwd)

			assert.equals("python", project_type)
		end)

		it("should return unknown for unrecognized project", function()
			-- Empty directory
			local project_type = scanner.detect_project_type(test_cwd)

			assert.equals("unknown", project_type)
		end)
	end)

	describe("parse_package_json", function()
		it("should parse dependencies from package.json", function()
			local pkg_content = [[{
				"name": "test",
				"dependencies": {
					"express": "^4.18.0",
					"lodash": "^4.17.0"
				},
				"devDependencies": {
					"jest": "^29.0.0"
				}
			}]]
			utils.write_file(test_cwd .. "/package.json", pkg_content)

			local result = scanner.parse_package_json(test_cwd)

			assert.is_table(result.dependencies)
			assert.is_table(result.dev_dependencies)
			assert.equals("^4.18.0", result.dependencies.express)
			assert.equals("^4.17.0", result.dependencies.lodash)
			assert.equals("^29.0.0", result.dev_dependencies.jest)
		end)

		it("should return empty tables when package.json does not exist", function()
			local result = scanner.parse_package_json(test_cwd)

			assert.is_table(result.dependencies)
			assert.is_table(result.dev_dependencies)
			assert.equals(0, vim.tbl_count(result.dependencies))
		end)

		it("should handle malformed JSON gracefully", function()
			utils.write_file(test_cwd .. "/package.json", "not valid json")

			local result = scanner.parse_package_json(test_cwd)

			assert.is_table(result.dependencies)
			assert.equals(0, vim.tbl_count(result.dependencies))
		end)
	end)

	describe("parse_cargo_toml", function()
		it("should parse dependencies from Cargo.toml", function()
			local cargo_content = [[
[package]
name = "test"

[dependencies]
serde = "1.0"
tokio = "1.28"

[dev-dependencies]
tempfile = "3.5"
]]
			utils.write_file(test_cwd .. "/Cargo.toml", cargo_content)

			local result = scanner.parse_cargo_toml(test_cwd)

			assert.is_table(result.dependencies)
			assert.equals("1.0", result.dependencies.serde)
			assert.equals("1.28", result.dependencies.tokio)
			assert.equals("3.5", result.dev_dependencies.tempfile)
		end)

		it("should return empty tables when Cargo.toml does not exist", function()
			local result = scanner.parse_cargo_toml(test_cwd)

			assert.equals(0, vim.tbl_count(result.dependencies))
		end)
	end)

	describe("parse_go_mod", function()
		it("should parse dependencies from go.mod", function()
			local go_mod_content = [[
module example.com/test

go 1.21

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/stretchr/testify v1.8.4
)
]]
			utils.write_file(test_cwd .. "/go.mod", go_mod_content)

			local result = scanner.parse_go_mod(test_cwd)

			assert.is_table(result.dependencies)
			assert.equals("v1.9.1", result.dependencies["github.com/gin-gonic/gin"])
			assert.equals("v1.8.4", result.dependencies["github.com/stretchr/testify"])
		end)
	end)

	describe("should_ignore", function()
		it("should ignore hidden files", function()
			local config = { excluded_dirs = {} }

			assert.is_true(scanner.should_ignore(".hidden", config))
			assert.is_true(scanner.should_ignore(".git", config))
		end)

		it("should ignore node_modules", function()
			local config = { excluded_dirs = {} }

			assert.is_true(scanner.should_ignore("node_modules", config))
		end)

		it("should ignore configured directories", function()
			local config = { excluded_dirs = { "custom_ignore" } }

			assert.is_true(scanner.should_ignore("custom_ignore", config))
		end)

		it("should not ignore regular files", function()
			local config = { excluded_dirs = {} }

			assert.is_false(scanner.should_ignore("main.lua", config))
			assert.is_false(scanner.should_ignore("src", config))
		end)
	end)

	describe("should_index", function()
		it("should index files with allowed extensions", function()
			vim.fn.mkdir(test_cwd .. "/src", "p")
			utils.write_file(test_cwd .. "/src/main.lua", "-- test")

			local config = {
				index_extensions = { "lua", "ts", "js" },
				max_file_size = 100000,
				excluded_dirs = {},
			}

			assert.is_true(scanner.should_index(test_cwd .. "/src/main.lua", config))
		end)

		it("should not index coder files", function()
			utils.write_file(test_cwd .. "/main.coder.lua", "-- test")

			local config = {
				index_extensions = { "lua" },
				max_file_size = 100000,
				excluded_dirs = {},
			}

			assert.is_false(scanner.should_index(test_cwd .. "/main.coder.lua", config))
		end)

		it("should not index files with disallowed extensions", function()
			utils.write_file(test_cwd .. "/image.png", "binary")

			local config = {
				index_extensions = { "lua", "ts", "js" },
				max_file_size = 100000,
				excluded_dirs = {},
			}

			assert.is_false(scanner.should_index(test_cwd .. "/image.png", config))
		end)
	end)

	describe("get_indexable_files", function()
		it("should return list of indexable files", function()
			vim.fn.mkdir(test_cwd .. "/src", "p")
			utils.write_file(test_cwd .. "/src/main.lua", "-- main")
			utils.write_file(test_cwd .. "/src/utils.lua", "-- utils")
			utils.write_file(test_cwd .. "/README.md", "# Readme")

			local config = {
				index_extensions = { "lua" },
				max_file_size = 100000,
				excluded_dirs = { "node_modules" },
			}

			local files = scanner.get_indexable_files(test_cwd, config)

			assert.equals(2, #files)
		end)

		it("should skip ignored directories", function()
			vim.fn.mkdir(test_cwd .. "/src", "p")
			vim.fn.mkdir(test_cwd .. "/node_modules", "p")
			utils.write_file(test_cwd .. "/src/main.lua", "-- main")
			utils.write_file(test_cwd .. "/node_modules/package.lua", "-- ignore")

			local config = {
				index_extensions = { "lua" },
				max_file_size = 100000,
				excluded_dirs = { "node_modules" },
			}

			local files = scanner.get_indexable_files(test_cwd, config)

			-- Should only include src/main.lua
			assert.equals(1, #files)
		end)
	end)

	describe("get_language", function()
		it("should return correct language for extensions", function()
			assert.equals("lua", scanner.get_language("test.lua"))
			assert.equals("typescript", scanner.get_language("test.ts"))
			assert.equals("javascript", scanner.get_language("test.js"))
			assert.equals("python", scanner.get_language("test.py"))
			assert.equals("go", scanner.get_language("test.go"))
			assert.equals("rust", scanner.get_language("test.rs"))
		end)

		it("should return extension as fallback", function()
			assert.equals("unknown", scanner.get_language("test.unknown"))
		end)
	end)
end)
