---@diagnostic disable: undefined-global
-- Tests for intent classification
-- NOTE: Intent classification has been migrated to the Python agent.
-- These tests are kept for reference but marked as pending.

describe("intent (MIGRATED TO PYTHON AGENT)", function()
	pending("detect - migrated to Python agent", function() end)
	pending("modifies_code - migrated to Python agent", function() end)
	pending("is_replacement - migrated to Python agent", function() end)
	pending("is_insertion - migrated to Python agent", function() end)
	pending("get_prompt_modifier - migrated to Python agent", function() end)
	pending("format - migrated to Python agent", function() end)
end)

-- Tests for location-based action override (Lua-side intent detection)
describe("intent location override", function()
	local intent

	before_each(function()
		intent = require("codetyper.core.intent")
	end)

	describe("append location patterns", function()
		it("should override action to append when 'at the end' is present", function()
			local result = intent.detect("add gitignore for typescript at the end of the file")
			assert.equals("append", result.action)
		end)

		it("should override action to append when 'at the bottom' is present", function()
			local result = intent.detect("add a new function at the bottom")
			assert.equals("append", result.action)
		end)

		it("should override action to append when 'to the end' is present", function()
			local result = intent.detect("insert comment to the end")
			assert.equals("append", result.action)
		end)
	end)

	describe("prepend location patterns", function()
		it("should override action to prepend when 'at the top' is present", function()
			local result = intent.detect("add imports at the top")
			assert.equals("prepend", result.action)
		end)

		it("should override action to prepend when 'at the beginning' is present", function()
			local result = intent.detect("insert header at the beginning")
			assert.equals("prepend", result.action)
		end)
	end)

	describe("no location override", function()
		it("should use default action when no location pattern is present", function()
			local result = intent.detect("add a new function")
			assert.equals("insert", result.action) -- default for 'add' intent
		end)

		it("should use default action for fix intent", function()
			local result = intent.detect("fix the bug in this function")
			assert.equals("replace", result.action) -- default for 'fix' intent
		end)
	end)
end)
