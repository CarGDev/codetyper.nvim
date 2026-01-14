---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/preferences.lua
-- Note: UI tests (floating window) are skipped per testing guidelines

describe("preferences", function()
	local preferences
	local utils

	-- Mock cwd for testing
	local test_cwd = "/tmp/codetyper_test_prefs"

	before_each(function()
		-- Reset modules
		package.loaded["codetyper.preferences"] = nil
		package.loaded["codetyper.utils"] = nil

		preferences = require("codetyper.preferences")
		utils = require("codetyper.utils")

		-- Clear cache before each test
		preferences.clear_cache()

		-- Create test directory
		vim.fn.mkdir(test_cwd, "p")
		vim.fn.mkdir(test_cwd .. "/.coder", "p")

		-- Mock getcwd to return test directory
		vim.fn.getcwd = function()
			return test_cwd
		end
	end)

	after_each(function()
		-- Clean up test directory
		vim.fn.delete(test_cwd, "rf")
	end)

	describe("load", function()
		it("should return defaults when no preferences file exists", function()
			local prefs = preferences.load()

			assert.is_table(prefs)
			assert.is_nil(prefs.auto_process)
			assert.is_false(prefs.asked_auto_process)
		end)

		it("should load preferences from file", function()
			-- Create preferences file
			local path = test_cwd .. "/.coder/preferences.json"
			utils.write_file(path, '{"auto_process":true,"asked_auto_process":true}')

			local prefs = preferences.load()

			assert.is_true(prefs.auto_process)
			assert.is_true(prefs.asked_auto_process)
		end)

		it("should merge file preferences with defaults", function()
			-- Create partial preferences file
			local path = test_cwd .. "/.coder/preferences.json"
			utils.write_file(path, '{"auto_process":false}')

			local prefs = preferences.load()

			assert.is_false(prefs.auto_process)
			-- Default for asked_auto_process should be preserved
			assert.is_false(prefs.asked_auto_process)
		end)

		it("should cache preferences", function()
			local prefs1 = preferences.load()
			prefs1.test_value = "cached"

			-- Load again - should get cached version
			local prefs2 = preferences.load()

			assert.equals("cached", prefs2.test_value)
		end)

		it("should handle invalid JSON gracefully", function()
			local path = test_cwd .. "/.coder/preferences.json"
			utils.write_file(path, "not valid json {{{")

			local prefs = preferences.load()

			-- Should return defaults
			assert.is_table(prefs)
			assert.is_nil(prefs.auto_process)
		end)
	end)

	describe("save", function()
		it("should save preferences to file", function()
			local prefs = {
				auto_process = true,
				asked_auto_process = true,
			}

			preferences.save(prefs)

			-- Verify file was created
			local path = test_cwd .. "/.coder/preferences.json"
			local content = utils.read_file(path)
			assert.is_truthy(content)

			local decoded = vim.json.decode(content)
			assert.is_true(decoded.auto_process)
			assert.is_true(decoded.asked_auto_process)
		end)

		it("should update cache after save", function()
			local prefs = {
				auto_process = true,
				asked_auto_process = true,
			}

			preferences.save(prefs)

			-- Load should return the saved values from cache
			local loaded = preferences.load()
			assert.is_true(loaded.auto_process)
		end)

		it("should create .coder directory if it does not exist", function()
			-- Remove .coder directory
			vim.fn.delete(test_cwd .. "/.coder", "rf")

			local prefs = { auto_process = false }
			preferences.save(prefs)

			-- Directory should be created
			assert.equals(1, vim.fn.isdirectory(test_cwd .. "/.coder"))
		end)
	end)

	describe("get", function()
		it("should get a specific preference value", function()
			local path = test_cwd .. "/.coder/preferences.json"
			utils.write_file(path, '{"auto_process":true}')

			local value = preferences.get("auto_process")

			assert.is_true(value)
		end)

		it("should return nil for non-existent key", function()
			local value = preferences.get("non_existent_key")

			assert.is_nil(value)
		end)
	end)

	describe("set", function()
		it("should set a specific preference value", function()
			preferences.set("auto_process", true)

			local value = preferences.get("auto_process")
			assert.is_true(value)
		end)

		it("should persist the value to file", function()
			preferences.set("auto_process", false)

			-- Clear cache and reload
			preferences.clear_cache()
			local value = preferences.get("auto_process")

			assert.is_false(value)
		end)
	end)

	describe("is_auto_process_enabled", function()
		it("should return nil when not set", function()
			local result = preferences.is_auto_process_enabled()

			assert.is_nil(result)
		end)

		it("should return true when enabled", function()
			preferences.set("auto_process", true)

			local result = preferences.is_auto_process_enabled()

			assert.is_true(result)
		end)

		it("should return false when disabled", function()
			preferences.set("auto_process", false)

			local result = preferences.is_auto_process_enabled()

			assert.is_false(result)
		end)
	end)

	describe("set_auto_process", function()
		it("should set auto_process to true", function()
			preferences.set_auto_process(true)

			assert.is_true(preferences.is_auto_process_enabled())
			assert.is_true(preferences.has_asked_auto_process())
		end)

		it("should set auto_process to false", function()
			preferences.set_auto_process(false)

			assert.is_false(preferences.is_auto_process_enabled())
			assert.is_true(preferences.has_asked_auto_process())
		end)

		it("should also set asked_auto_process to true", function()
			preferences.set_auto_process(true)

			assert.is_true(preferences.has_asked_auto_process())
		end)
	end)

	describe("has_asked_auto_process", function()
		it("should return false when not asked", function()
			local result = preferences.has_asked_auto_process()

			assert.is_false(result)
		end)

		it("should return true after setting auto_process", function()
			preferences.set_auto_process(true)

			local result = preferences.has_asked_auto_process()

			assert.is_true(result)
		end)
	end)

	describe("clear_cache", function()
		it("should clear cached preferences", function()
			-- Load to populate cache
			local prefs = preferences.load()
			prefs.test_marker = "before_clear"

			-- Clear cache
			preferences.clear_cache()

			-- Load again - should not have the marker
			local prefs_after = preferences.load()
			assert.is_nil(prefs_after.test_marker)
		end)
	end)

	describe("toggle_auto_process", function()
		it("should toggle from nil to true", function()
			-- Initially nil
			assert.is_nil(preferences.is_auto_process_enabled())

			preferences.toggle_auto_process()

			-- Should be true (not nil becomes true)
			assert.is_true(preferences.is_auto_process_enabled())
		end)

		it("should toggle from true to false", function()
			preferences.set_auto_process(true)

			preferences.toggle_auto_process()

			assert.is_false(preferences.is_auto_process_enabled())
		end)

		it("should toggle from false to true", function()
			preferences.set_auto_process(false)

			preferences.toggle_auto_process()

			assert.is_true(preferences.is_auto_process_enabled())
		end)
	end)
end)
