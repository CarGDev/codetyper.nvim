--- Tests for brain/learners pattern detection and extraction
describe("brain.learners", function()
	local pattern_learner

	before_each(function()
		-- Clear module cache
		package.loaded["codetyper.brain.learners.pattern"] = nil
		package.loaded["codetyper.brain.types"] = nil

		pattern_learner = require("codetyper.brain.learners.pattern")
	end)

	describe("pattern learner detection", function()
		it("should detect code_completion events", function()
			local event = { type = "code_completion", data = {} }
			assert.is_true(pattern_learner.detect(event))
		end)

		it("should detect file_indexed events", function()
			local event = { type = "file_indexed", data = {} }
			assert.is_true(pattern_learner.detect(event))
		end)

		it("should detect code_analyzed events", function()
			local event = { type = "code_analyzed", data = {} }
			assert.is_true(pattern_learner.detect(event))
		end)

		it("should detect pattern_detected events", function()
			local event = { type = "pattern_detected", data = {} }
			assert.is_true(pattern_learner.detect(event))
		end)

		it("should NOT detect plain 'pattern' type events", function()
			-- This was the bug - 'pattern' type was not in the valid_types list
			local event = { type = "pattern", data = {} }
			assert.is_false(pattern_learner.detect(event))
		end)

		it("should NOT detect unknown event types", function()
			local event = { type = "unknown_type", data = {} }
			assert.is_false(pattern_learner.detect(event))
		end)

		it("should NOT detect nil events", function()
			assert.is_false(pattern_learner.detect(nil))
		end)

		it("should NOT detect events without type", function()
			local event = { data = {} }
			assert.is_false(pattern_learner.detect(event))
		end)
	end)

	describe("pattern learner extraction", function()
		it("should extract from pattern_detected events", function()
			local event = {
				type = "pattern_detected",
				file = "/path/to/file.lua",
				data = {
					name = "Test pattern",
					description = "Pattern description",
					language = "lua",
					symbols = { "func1", "func2" },
				},
			}

			local extracted = pattern_learner.extract(event)

			assert.is_not_nil(extracted)
			assert.equals("Test pattern", extracted.summary)
			assert.equals("Pattern description", extracted.detail)
			assert.equals("lua", extracted.lang)
			assert.equals("/path/to/file.lua", extracted.file)
		end)

		it("should handle pattern_detected with minimal data", function()
			local event = {
				type = "pattern_detected",
				file = "/path/to/file.lua",
				data = {
					name = "Minimal pattern",
				},
			}

			local extracted = pattern_learner.extract(event)

			assert.is_not_nil(extracted)
			assert.equals("Minimal pattern", extracted.summary)
			assert.equals("Minimal pattern", extracted.detail)
		end)

		it("should extract from code_completion events", function()
			local event = {
				type = "code_completion",
				file = "/path/to/file.lua",
				data = {
					intent = "add function",
					code = "function test() end",
					language = "lua",
				},
			}

			local extracted = pattern_learner.extract(event)

			assert.is_not_nil(extracted)
			assert.is_true(extracted.summary:find("Code pattern") ~= nil)
			assert.equals("function test() end", extracted.detail)
		end)
	end)

	describe("should_learn validation", function()
		it("should accept valid patterns", function()
			local data = {
				summary = "Valid pattern summary",
				detail = "This is a detailed description of the pattern",
			}
			assert.is_true(pattern_learner.should_learn(data))
		end)

		it("should reject patterns without summary", function()
			local data = {
				summary = "",
				detail = "Some detail",
			}
			assert.is_false(pattern_learner.should_learn(data))
		end)

		it("should reject patterns with nil summary", function()
			local data = {
				summary = nil,
				detail = "Some detail",
			}
			assert.is_false(pattern_learner.should_learn(data))
		end)

		it("should reject patterns with very short detail", function()
			local data = {
				summary = "Valid summary",
				detail = "short", -- Less than 10 chars
			}
			assert.is_false(pattern_learner.should_learn(data))
		end)

		it("should reject whitespace-only summaries", function()
			local data = {
				summary = "   ",
				detail = "Some valid detail here",
			}
			assert.is_false(pattern_learner.should_learn(data))
		end)
	end)
end)
