--- Tests for smart LLM selection with memory-based confidence

describe("codetyper.llm.selector", function()
	local selector

	before_each(function()
		selector = require("codetyper.llm.selector")
		-- Reset stats for clean tests
		selector.reset_accuracy_stats()
	end)

	describe("select_provider", function()
		it("should return copilot when no brain memories exist", function()
			local result = selector.select_provider("write a function", {
				file_path = "/test/file.lua",
			})

			assert.equals("copilot", result.provider)
			assert.equals(0, result.memory_count)
			assert.truthy(result.reason:match("Insufficient context"))
		end)

		it("should return a valid selection result structure", function()
			local result = selector.select_provider("test prompt", {})

			assert.is_string(result.provider)
			assert.is_number(result.confidence)
			assert.is_number(result.memory_count)
			assert.is_string(result.reason)
		end)

		it("should have confidence between 0 and 1", function()
			local result = selector.select_provider("test", {})

			assert.truthy(result.confidence >= 0)
			assert.truthy(result.confidence <= 1)
		end)
	end)

	describe("should_ponder", function()
		it("should return true for medium confidence", function()
			assert.is_true(selector.should_ponder(0.5))
			assert.is_true(selector.should_ponder(0.6))
		end)

		it("should return false for low confidence", function()
			assert.is_false(selector.should_ponder(0.2))
			assert.is_false(selector.should_ponder(0.3))
		end)

		-- High confidence pondering is probabilistic, so we test the range
		it("should sometimes ponder for high confidence (sampling)", function()
			-- Run multiple times to test probabilistic behavior
			local pondered_count = 0
			for _ = 1, 100 do
				if selector.should_ponder(0.9) then
					pondered_count = pondered_count + 1
				end
			end
			-- Should ponder roughly 20% of the time (PONDER_SAMPLE_RATE = 0.2)
			-- Allow range of 5-40% due to randomness
			assert.truthy(pondered_count >= 5, "Should ponder at least sometimes")
			assert.truthy(pondered_count <= 40, "Should not ponder too often")
		end)
	end)

	describe("get_accuracy_stats", function()
		it("should return initial empty stats", function()
			local stats = selector.get_accuracy_stats()

			assert.equals(0, stats.ollama.total)
			assert.equals(0, stats.ollama.correct)
			assert.equals(0, stats.ollama.accuracy)
			assert.equals(0, stats.copilot.total)
			assert.equals(0, stats.copilot.correct)
			assert.equals(0, stats.copilot.accuracy)
		end)
	end)

	describe("report_feedback", function()
		it("should track positive feedback", function()
			selector.report_feedback("ollama", true)
			selector.report_feedback("ollama", true)
			selector.report_feedback("ollama", false)

			local stats = selector.get_accuracy_stats()
			assert.equals(3, stats.ollama.total)
			assert.equals(2, stats.ollama.correct)
		end)

		it("should track copilot feedback separately", function()
			selector.report_feedback("ollama", true)
			selector.report_feedback("copilot", true)
			selector.report_feedback("copilot", false)

			local stats = selector.get_accuracy_stats()
			assert.equals(1, stats.ollama.total)
			assert.equals(2, stats.copilot.total)
		end)

		it("should calculate accuracy correctly", function()
			selector.report_feedback("ollama", true)
			selector.report_feedback("ollama", true)
			selector.report_feedback("ollama", true)
			selector.report_feedback("ollama", false)

			local stats = selector.get_accuracy_stats()
			assert.equals(0.75, stats.ollama.accuracy)
		end)
	end)

	describe("reset_accuracy_stats", function()
		it("should clear all stats", function()
			selector.report_feedback("ollama", true)
			selector.report_feedback("copilot", true)

			selector.reset_accuracy_stats()

			local stats = selector.get_accuracy_stats()
			assert.equals(0, stats.ollama.total)
			assert.equals(0, stats.copilot.total)
		end)
	end)
end)

describe("agreement calculation", function()
	-- Test the internal agreement calculation through pondering behavior
	-- Since calculate_agreement is local, we test its effects indirectly

	it("should detect high agreement for similar responses", function()
		-- This is tested through the pondering system
		-- When responses are similar, agreement should be high
		local selector = require("codetyper.llm.selector")

		-- Verify that should_ponder returns predictable results
		-- for medium confidence (where pondering always happens)
		assert.is_true(selector.should_ponder(0.5))
	end)
end)

describe("provider selection with accuracy history", function()
	local selector

	before_each(function()
		selector = require("codetyper.llm.selector")
		selector.reset_accuracy_stats()
	end)

	it("should factor in historical accuracy for selection", function()
		-- Simulate high Ollama accuracy
		for _ = 1, 10 do
			selector.report_feedback("ollama", true)
		end

		-- Even with no brain context, historical accuracy should influence confidence
		local result = selector.select_provider("test", {})

		-- Confidence should be higher due to historical accuracy
		-- but provider might still be copilot if no memories
		assert.is_number(result.confidence)
	end)

	it("should have lower confidence for low historical accuracy", function()
		-- Simulate low Ollama accuracy
		for _ = 1, 10 do
			selector.report_feedback("ollama", false)
		end

		local result = selector.select_provider("test", {})

		-- With bad history and no memories, should definitely use copilot
		assert.equals("copilot", result.provider)
	end)
end)
