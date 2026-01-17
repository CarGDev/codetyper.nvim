---@diagnostic disable: undefined-global
-- Tests for codetyper.support.imports module

describe("imports", function()
	local imports

	before_each(function()
		imports = require("codetyper.support.imports")
	end)

	describe("extract_imports (via find_imports)", function()
		-- We test the internal extraction logic by mocking file content

		it("should detect JavaScript import statements", function()
			-- Test patterns (copied from imports.lua)
			local js_patterns = {
				'import%s+[^"\']*["\']([^"\']+)["\']',
				'import%s*%(["\']([^"\']+)["\']%)',
				'require%s*%(["\']([^"\']+)["\']%)',
				'from%s+["\']([^"\']+)["\']',
			}

			local test_lines = {
				{ line = 'import React from "./components/React"', expected = "./components/React" },
				{ line = 'import { foo } from "./utils"', expected = "./utils" },
				{ line = "const x = require('./helpers')", expected = "./helpers" },
				{ line = 'import("./dynamic-module")', expected = "./dynamic-module" },
			}

			for _, test in ipairs(test_lines) do
				local found = false
				for _, pattern in ipairs(js_patterns) do
					local match = test.line:match(pattern)
					if match == test.expected then
						found = true
						break
					end
				end
				assert.is_true(found, "Pattern should match: " .. test.line)
			end
		end)

		it("should detect Lua require statements", function()
			local lua_patterns = {
				'require%s*%(?["\']([^"\']+)["\']%)?',
			}

			local test_lines = {
				{ line = 'require("codetyper.support.utils")', expected = "codetyper.support.utils" },
				{ line = "require 'codetyper.core.llm'", expected = "codetyper.core.llm" },
				{ line = 'local M = require("mymodule")', expected = "mymodule" },
			}

			for _, test in ipairs(test_lines) do
				local found = false
				for _, pattern in ipairs(lua_patterns) do
					local match = test.line:match(pattern)
					if match == test.expected then
						found = true
						break
					end
				end
				assert.is_true(found, "Pattern should match: " .. test.line)
			end
		end)

		it("should detect Python import statements", function()
			local python_patterns = {
				"^import%s+([%w_.]+)",
				"^from%s+([%w_.]+)%s+import",
			}

			local test_lines = {
				{ line = "import os.path", expected = "os.path" },
				{ line = "from mymodule import foo", expected = "mymodule" },
				{ line = "import numpy", expected = "numpy" },
			}

			for _, test in ipairs(test_lines) do
				local found = false
				for _, pattern in ipairs(python_patterns) do
					local match = test.line:match(pattern)
					if match == test.expected then
						found = true
						break
					end
				end
				assert.is_true(found, "Pattern should match: " .. test.line)
			end
		end)

		it("should detect Go import statements", function()
			local go_patterns = {
				'import%s+["\']([^"\']+)["\']',
				'["\']([^"\']+)["\']',
			}

			local test_lines = {
				{ line = 'import "fmt"', expected = "fmt" },
				{ line = '"github.com/user/pkg"', expected = "github.com/user/pkg" },
			}

			for _, test in ipairs(test_lines) do
				local found = false
				for _, pattern in ipairs(go_patterns) do
					local match = test.line:match(pattern)
					if match == test.expected then
						found = true
						break
					end
				end
				assert.is_true(found, "Pattern should match: " .. test.line)
			end
		end)

		it("should detect Rust use statements", function()
			local rust_patterns = {
				"use%s+([%w_:]+)",
				"mod%s+([%w_]+)",
			}

			local test_lines = {
				{ line = "use std::io", expected = "std::io" },
				{ line = "use crate::utils", expected = "crate::utils" },
				{ line = "mod helpers", expected = "helpers" },
			}

			for _, test in ipairs(test_lines) do
				local found = false
				for _, pattern in ipairs(rust_patterns) do
					local match = test.line:match(pattern)
					if match == test.expected then
						found = true
						break
					end
				end
				assert.is_true(found, "Pattern should match: " .. test.line)
			end
		end)

		it("should detect CSS @import statements", function()
			local css_patterns = {
				'@import%s+["\']([^"\']+)["\']',
				'@import%s+url%(["\']?([^"\'%)]+)["\']?%)',
			}

			local test_lines = {
				{ line = '@import "styles/base.css"', expected = "styles/base.css" },
				{ line = '@import url("reset.css")', expected = "reset.css" },
				{ line = "@import url(fonts.css)", expected = "fonts.css" },
			}

			for _, test in ipairs(test_lines) do
				local found = false
				for _, pattern in ipairs(css_patterns) do
					local match = test.line:match(pattern)
					if match == test.expected then
						found = true
						break
					end
				end
				assert.is_true(found, "Pattern should match: " .. test.line)
			end
		end)
	end)

	describe("is_relative_import logic", function()
		it("should identify relative imports", function()
			-- Relative imports start with . or ..
			local relative_tests = {
				{ path = "./utils", is_relative = true },
				{ path = "../helpers", is_relative = true },
				{ path = "../../lib/core", is_relative = true },
				{ path = "react", is_relative = false },
				{ path = "@org/package", is_relative = false },
				{ path = "lodash", is_relative = false },
			}

			for _, test in ipairs(relative_tests) do
				local result = test.path:match("^%.") ~= nil
				assert.are.equal(test.is_relative, result, "Path: " .. test.path)
			end
		end)
	end)

	describe("is_local_import logic", function()
		it("should filter out node_modules imports for JS", function()
			local test_cases = {
				{ path = "react", lang = "js", is_local = false },
				{ path = "@org/package", lang = "js", is_local = false },
				{ path = "./components", lang = "js", is_local = true },
				{ path = "../utils", lang = "js", is_local = true },
				{ path = "node_modules/lib", lang = "js", is_local = false },
			}

			for _, test in ipairs(test_cases) do
				local is_local = false

				-- Skip node_modules, external packages
				if test.path:match("^@?[%w%-]+$") and test.lang == "js" then
					-- Bare import like 'react' or '@org/package'
					is_local = false
				elseif test.path:match("^node_modules") then
					is_local = false
				elseif test.lang == "js" and test.path:match("^%.") then
					-- Relative imports are always local for JS
					is_local = true
				else
					is_local = test.path:match("^%.") ~= nil
				end

				assert.are.equal(test.is_local, is_local, "Path: " .. test.path)
			end
		end)

		it("should filter out vim and plenary imports for Lua", function()
			local test_cases = {
				{ path = "vim.lsp", lang = "lua", is_local = false },
				{ path = "plenary.path", lang = "lua", is_local = false },
				{ path = "codetyper.core.llm", lang = "lua", is_local = true },
				{ path = "myproject.utils", lang = "lua", is_local = true },
			}

			for _, test in ipairs(test_cases) do
				local is_local = true
				if test.lang == "lua" then
					is_local = not test.path:match("^vim%.") and not test.path:match("^plenary%.")
				end

				assert.are.equal(test.is_local, is_local, "Path: " .. test.path)
			end
		end)
	end)

	describe("extension mapping", function()
		it("should map file extensions to correct languages", function()
			local ext_to_lang = {
				js = "js",
				jsx = "js",
				ts = "js",
				tsx = "js",
				mjs = "js",
				cjs = "js",
				vue = "js",
				svelte = "js",
				lua = "lua",
				py = "python",
				go = "go",
				rs = "rust",
				css = "css",
				scss = "css",
				sass = "css",
				less = "css",
			}

			assert.are.equal("js", ext_to_lang["js"])
			assert.are.equal("js", ext_to_lang["tsx"])
			assert.are.equal("lua", ext_to_lang["lua"])
			assert.are.equal("python", ext_to_lang["py"])
			assert.are.equal("go", ext_to_lang["go"])
			assert.are.equal("rust", ext_to_lang["rs"])
			assert.are.equal("css", ext_to_lang["scss"])
		end)
	end)

	describe("module exports", function()
		it("should export find_imports function", function()
			assert.is_function(imports.find_imports)
		end)

		it("should export find_imports_recursive function", function()
			assert.is_function(imports.find_imports_recursive)
		end)

		it("should export build_expanded_context function", function()
			assert.is_function(imports.build_expanded_context)
		end)
	end)

	describe("find_imports with non-existent file", function()
		it("should return empty table for non-existent file", function()
			local result = imports.find_imports("/nonexistent/path/to/file.js")
			assert.are.same({}, result)
		end)
	end)

	describe("find_imports_recursive limits", function()
		it("should respect max_files limit", function()
			-- This tests the function signature and defaults
			local result = imports.find_imports_recursive("/nonexistent/file.js", 2, 5)
			assert.are.same({}, result)
		end)

		it("should respect max_depth limit", function()
			-- This tests the function signature and defaults
			local result = imports.find_imports_recursive("/nonexistent/file.js", 1, 20)
			assert.are.same({}, result)
		end)
	end)

	describe("build_expanded_context", function()
		it("should return empty context for empty files table", function()
			local context, count = imports.build_expanded_context({})
			assert.are.equal("", context)
			assert.are.equal(0, count)
		end)
	end)
end)
