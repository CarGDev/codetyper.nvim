---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/agent/confidence.lua

describe("confidence", function()
	local confidence = require("codetyper.agent.confidence")

	describe("weights", function()
		it("should have weights that sum to 1.0", function()
			local total = 0
			for _, weight in pairs(confidence.weights) do
				total = total + weight
			end
			assert.is_near(1.0, total, 0.001)
		end)
	end)

	describe("score", function()
		it("should return 0 for empty response", function()
			local score, breakdown = confidence.score("", "some prompt")

			assert.equals(0, score)
			assert.equals(0, breakdown.weighted_total)
		end)

		it("should return high score for good response", function()
			local good_response = [[
function validateEmail(email)
  local pattern = "^[%w%.]+@[%w%.]+%.%w+$"
  return string.match(email, pattern) ~= nil
end
]]
			local score, breakdown = confidence.score(good_response, "create email validator")

			assert.is_true(score > 0.7)
			assert.is_true(breakdown.syntax > 0.5)
		end)

		it("should return lower score for response with uncertainty", function()
			local uncertain_response = [[
-- I'm not sure if this is correct, maybe try:
function doSomething()
  -- TODO: implement this
  -- placeholder code here
end
]]
			local score, _ = confidence.score(uncertain_response, "implement function")

			assert.is_true(score < 0.7)
		end)

		it("should penalize unbalanced brackets", function()
			local unbalanced = [[
function test() {
  if (true) {
    console.log("missing bracket")
]]
			local _, breakdown = confidence.score(unbalanced, "test")

			assert.is_true(breakdown.syntax < 0.7)
		end)

		it("should penalize short responses to long prompts", function()
			local long_prompt = "Create a comprehensive function that handles user authentication, " ..
				"validates credentials against the database, generates JWT tokens, " ..
				"handles refresh tokens, and logs all authentication attempts"
			local short_response = "done"

			local score, breakdown = confidence.score(short_response, long_prompt)

			assert.is_true(breakdown.length < 0.5)
		end)

		it("should penalize repetitive code", function()
			local repetitive = [[
console.log("test");
console.log("test");
console.log("test");
console.log("test");
console.log("test");
console.log("test");
console.log("test");
console.log("test");
]]
			local _, breakdown = confidence.score(repetitive, "test")

			assert.is_true(breakdown.repetition < 0.7)
		end)

		it("should penalize truncated responses", function()
			local truncated = [[
function process(data) {
  const result = data.map(item => {
    return {
      id: item.id,
      name: item...
]]
			local _, breakdown = confidence.score(truncated, "test")

			assert.is_true(breakdown.truncation < 1.0)
		end)
	end)

	describe("needs_escalation", function()
		it("should return true for low confidence", function()
			assert.is_true(confidence.needs_escalation(0.5, 0.7))
			assert.is_true(confidence.needs_escalation(0.3, 0.7))
		end)

		it("should return false for high confidence", function()
			assert.is_false(confidence.needs_escalation(0.8, 0.7))
			assert.is_false(confidence.needs_escalation(0.95, 0.7))
		end)

		it("should use default threshold of 0.7", function()
			assert.is_true(confidence.needs_escalation(0.6))
			assert.is_false(confidence.needs_escalation(0.8))
		end)
	end)

	describe("level_name", function()
		it("should return correct level names", function()
			assert.equals("excellent", confidence.level_name(0.95))
			assert.equals("good", confidence.level_name(0.85))
			assert.equals("acceptable", confidence.level_name(0.75))
			assert.equals("uncertain", confidence.level_name(0.6))
			assert.equals("poor", confidence.level_name(0.3))
		end)
	end)

	describe("format_breakdown", function()
		it("should format breakdown correctly", function()
			local breakdown = {
				length = 0.8,
				uncertainty = 0.9,
				syntax = 1.0,
				repetition = 0.85,
				truncation = 0.95,
				weighted_total = 0.9,
			}

			local formatted = confidence.format_breakdown(breakdown)

			assert.is_true(formatted:match("len:0.80"))
			assert.is_true(formatted:match("unc:0.90"))
			assert.is_true(formatted:match("syn:1.00"))
		end)
	end)
end)
