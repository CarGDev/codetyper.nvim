--- Tests for coder file context injection
describe("coder context injection", function()
	local test_dir
	local original_filereadable

	before_each(function()
		test_dir = "/tmp/codetyper_coder_test_" .. os.time()
		vim.fn.mkdir(test_dir, "p")

		-- Store original function
		original_filereadable = vim.fn.filereadable
	end)

	after_each(function()
		vim.fn.delete(test_dir, "rf")
		vim.fn.filereadable = original_filereadable
	end)

	describe("get_coder_companion_path logic", function()
		-- Test the path generation logic (simulating the function behavior)
		local function get_coder_companion_path(target_path, file_exists_check)
			if not target_path or target_path == "" then
				return nil
			end

			-- Skip if target is already a coder file
			if target_path:match("%.coder%.") then
				return nil
			end

			local dir = vim.fn.fnamemodify(target_path, ":h")
			local name = vim.fn.fnamemodify(target_path, ":t:r")
			local ext = vim.fn.fnamemodify(target_path, ":e")

			local coder_path = dir .. "/" .. name .. ".coder." .. ext
			if file_exists_check(coder_path) then
				return coder_path
			end

			return nil
		end

		it("should generate correct coder path for source file", function()
			local target = "/path/to/file.ts"
			local expected = "/path/to/file.coder.ts"

			local path = get_coder_companion_path(target, function() return true end)

			assert.equals(expected, path)
		end)

		it("should return nil for empty path", function()
			local path = get_coder_companion_path("", function() return true end)
			assert.is_nil(path)
		end)

		it("should return nil for nil path", function()
			local path = get_coder_companion_path(nil, function() return true end)
			assert.is_nil(path)
		end)

		it("should return nil for coder files (avoid recursion)", function()
			local target = "/path/to/file.coder.ts"
			local path = get_coder_companion_path(target, function() return true end)
			assert.is_nil(path)
		end)

		it("should return nil if coder file doesn't exist", function()
			local target = "/path/to/file.ts"
			local path = get_coder_companion_path(target, function() return false end)
			assert.is_nil(path)
		end)

		it("should handle files with multiple dots", function()
			local target = "/path/to/my.component.ts"
			local expected = "/path/to/my.component.coder.ts"

			local path = get_coder_companion_path(target, function() return true end)

			assert.equals(expected, path)
		end)

		it("should handle different extensions", function()
			local test_cases = {
				{ target = "/path/file.lua", expected = "/path/file.coder.lua" },
				{ target = "/path/file.py", expected = "/path/file.coder.py" },
				{ target = "/path/file.js", expected = "/path/file.coder.js" },
				{ target = "/path/file.go", expected = "/path/file.coder.go" },
			}

			for _, tc in ipairs(test_cases) do
				local path = get_coder_companion_path(tc.target, function() return true end)
				assert.equals(tc.expected, path, "Failed for: " .. tc.target)
			end
		end)
	end)

	describe("coder content filtering", function()
		-- Test the filtering logic that skips template-only content
		local function has_meaningful_content(lines)
			for _, line in ipairs(lines) do
				local trimmed = line:gsub("^%s*", "")
				if not trimmed:match("^[%-#/]+%s*Coder companion")
					and not trimmed:match("^[%-#/]+%s*Use /@ @/")
					and not trimmed:match("^[%-#/]+%s*Example:")
					and not trimmed:match("^<!%-%-")
					and trimmed ~= ""
					and not trimmed:match("^[%-#/]+%s*$") then
					return true
				end
			end
			return false
		end

		it("should detect meaningful content", function()
			local lines = {
				"-- Coder companion for test.lua",
				"-- This file handles authentication",
				"/@",
				"Add login function",
				"@/",
			}
			assert.is_true(has_meaningful_content(lines))
		end)

		it("should reject template-only content", function()
			-- Template lines are filtered by specific patterns
			-- Only header comments that match the template format are filtered
			local lines = {
				"-- Coder companion for test.lua",
				"-- Use /@ @/ tags to write pseudo-code prompts",
				"-- Example:",
				"--",
				"",
			}
			assert.is_false(has_meaningful_content(lines))
		end)

		it("should detect pseudo-code content", function()
			local lines = {
				"-- Authentication module",
				"",
				"-- This module should:",
				"-- 1. Validate user credentials",
				"-- 2. Generate JWT tokens",
				"-- 3. Handle session management",
			}
			-- "-- Authentication module" doesn't match template patterns
			assert.is_true(has_meaningful_content(lines))
		end)

		it("should handle JavaScript style comments", function()
			local lines = {
				"// Coder companion for test.ts",
				"// Business logic for user authentication",
				"",
				"// The auth flow should:",
				"// 1. Check OAuth token",
				"// 2. Validate permissions",
			}
			-- "// Business logic..." doesn't match template patterns
			assert.is_true(has_meaningful_content(lines))
		end)

		it("should handle empty lines", function()
			local lines = {
				"",
				"",
				"",
			}
			assert.is_false(has_meaningful_content(lines))
		end)
	end)

	describe("context format", function()
		it("should format context with proper header", function()
			local function format_coder_context(content, ext)
				return string.format(
					"\n\n--- Business Context / Pseudo-code ---\n" ..
					"The following describes the intended behavior and design for this file:\n" ..
					"```%s\n%s\n```",
					ext,
					content
				)
			end

			local formatted = format_coder_context("-- Auth logic here", "lua")

			assert.is_true(formatted:find("Business Context") ~= nil)
			assert.is_true(formatted:find("```lua") ~= nil)
			assert.is_true(formatted:find("Auth logic here") ~= nil)
		end)
	end)
end)
