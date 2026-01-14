---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/agent/intent.lua

describe("intent", function()
	local intent = require("codetyper.agent.intent")

	describe("detect", function()
		describe("complete intent", function()
			it("should detect 'complete' keyword", function()
				local result = intent.detect("complete this function")
				assert.equals("complete", result.type)
				assert.equals("replace", result.action)
			end)

			it("should detect 'finish' keyword", function()
				local result = intent.detect("finish implementing this method")
				assert.equals("complete", result.type)
			end)

			it("should detect 'implement' keyword", function()
				local result = intent.detect("implement the sorting algorithm")
				assert.equals("complete", result.type)
			end)

			it("should detect 'todo' keyword", function()
				local result = intent.detect("fix the TODO here")
				assert.equals("complete", result.type)
			end)
		end)

		describe("refactor intent", function()
			it("should detect 'refactor' keyword", function()
				local result = intent.detect("refactor this messy code")
				assert.equals("refactor", result.type)
				assert.equals("replace", result.action)
			end)

			it("should detect 'rewrite' keyword", function()
				local result = intent.detect("rewrite using async/await")
				assert.equals("refactor", result.type)
			end)

			it("should detect 'simplify' keyword", function()
				local result = intent.detect("simplify this logic")
				assert.equals("refactor", result.type)
			end)

			it("should detect 'cleanup' keyword", function()
				local result = intent.detect("cleanup this code")
				assert.equals("refactor", result.type)
			end)
		end)

		describe("fix intent", function()
			it("should detect 'fix' keyword", function()
				local result = intent.detect("fix the bug in this function")
				assert.equals("fix", result.type)
				assert.equals("replace", result.action)
			end)

			it("should detect 'debug' keyword", function()
				local result = intent.detect("debug this issue")
				assert.equals("fix", result.type)
			end)

			it("should detect 'bug' keyword", function()
				local result = intent.detect("there's a bug here")
				assert.equals("fix", result.type)
			end)

			it("should detect 'error' keyword", function()
				local result = intent.detect("getting an error with this code")
				assert.equals("fix", result.type)
			end)
		end)

		describe("add intent", function()
			it("should detect 'add' keyword", function()
				local result = intent.detect("add input validation")
				assert.equals("add", result.type)
				assert.equals("insert", result.action)
			end)

			it("should detect 'create' keyword", function()
				local result = intent.detect("create a new helper function")
				assert.equals("add", result.type)
			end)

			it("should detect 'generate' keyword", function()
				local result = intent.detect("generate a utility function")
				assert.equals("add", result.type)
			end)
		end)

		describe("document intent", function()
			it("should detect 'document' keyword", function()
				local result = intent.detect("document this function")
				assert.equals("document", result.type)
				assert.equals("replace", result.action)
			end)

			it("should detect 'jsdoc' keyword", function()
				local result = intent.detect("add jsdoc comments")
				assert.equals("document", result.type)
			end)

			it("should detect 'comment' keyword", function()
				local result = intent.detect("add comments to explain")
				assert.equals("document", result.type)
			end)
		end)

		describe("test intent", function()
			it("should detect 'test' keyword", function()
				local result = intent.detect("write tests for this function")
				assert.equals("test", result.type)
				assert.equals("append", result.action)
			end)

			it("should detect 'unit test' keyword", function()
				local result = intent.detect("create unit tests")
				assert.equals("test", result.type)
			end)
		end)

		describe("optimize intent", function()
			it("should detect 'optimize' keyword", function()
				local result = intent.detect("optimize this loop")
				assert.equals("optimize", result.type)
				assert.equals("replace", result.action)
			end)

			it("should detect 'performance' keyword", function()
				local result = intent.detect("improve performance of this function")
				assert.equals("optimize", result.type)
			end)

			it("should detect 'faster' keyword", function()
				local result = intent.detect("make this faster")
				assert.equals("optimize", result.type)
			end)
		end)

		describe("explain intent", function()
			it("should detect 'explain' keyword", function()
				local result = intent.detect("explain what this does")
				assert.equals("explain", result.type)
				assert.equals("none", result.action)
			end)

			it("should detect 'what does' pattern", function()
				local result = intent.detect("what does this function do")
				assert.equals("explain", result.type)
			end)

			it("should detect 'how does' pattern", function()
				local result = intent.detect("how does this algorithm work")
				assert.equals("explain", result.type)
			end)
		end)

		describe("default intent", function()
			it("should default to 'add' for unknown prompts", function()
				local result = intent.detect("make it blue")
				assert.equals("add", result.type)
			end)
		end)

		describe("scope hints", function()
			it("should detect 'this function' scope hint", function()
				local result = intent.detect("refactor this function")
				assert.equals("function", result.scope_hint)
			end)

			it("should detect 'this class' scope hint", function()
				local result = intent.detect("document this class")
				assert.equals("class", result.scope_hint)
			end)

			it("should detect 'this file' scope hint", function()
				local result = intent.detect("test this file")
				assert.equals("file", result.scope_hint)
			end)
		end)

		describe("confidence", function()
			it("should have higher confidence with more keyword matches", function()
				local result1 = intent.detect("fix")
				local result2 = intent.detect("fix the bug error")

				assert.is_true(result2.confidence >= result1.confidence)
			end)

			it("should cap confidence at 1.0", function()
				local result = intent.detect("fix debug bug error issue solve")
				assert.is_true(result.confidence <= 1.0)
			end)
		end)
	end)

	describe("modifies_code", function()
		it("should return true for replacement intents", function()
			assert.is_true(intent.modifies_code({ action = "replace" }))
		end)

		it("should return true for insertion intents", function()
			assert.is_true(intent.modifies_code({ action = "insert" }))
		end)

		it("should return false for explain intent", function()
			assert.is_false(intent.modifies_code({ action = "none" }))
		end)
	end)

	describe("is_replacement", function()
		it("should return true for replace action", function()
			assert.is_true(intent.is_replacement({ action = "replace" }))
		end)

		it("should return false for insert action", function()
			assert.is_false(intent.is_replacement({ action = "insert" }))
		end)
	end)

	describe("is_insertion", function()
		it("should return true for insert action", function()
			assert.is_true(intent.is_insertion({ action = "insert" }))
		end)

		it("should return true for append action", function()
			assert.is_true(intent.is_insertion({ action = "append" }))
		end)

		it("should return false for replace action", function()
			assert.is_false(intent.is_insertion({ action = "replace" }))
		end)
	end)

	describe("get_prompt_modifier", function()
		it("should return modifier for each intent type", function()
			local types = { "complete", "refactor", "fix", "add", "document", "test", "optimize", "explain" }

			for _, type_name in ipairs(types) do
				local modifier = intent.get_prompt_modifier({ type = type_name })
				assert.is_truthy(modifier)
				assert.is_true(#modifier > 0)
			end
		end)

		it("should return add modifier for unknown type", function()
			local modifier = intent.get_prompt_modifier({ type = "unknown" })
			assert.is_truthy(modifier)
		end)
	end)

	describe("format", function()
		it("should format intent correctly", function()
			local i = {
				type = "refactor",
				scope_hint = "function",
				action = "replace",
				confidence = 0.85,
			}

			local formatted = intent.format(i)

			assert.is_true(formatted:match("refactor"))
			assert.is_true(formatted:match("function"))
			assert.is_true(formatted:match("replace"))
			assert.is_true(formatted:match("0.85"))
		end)

		it("should handle nil scope_hint", function()
			local i = {
				type = "add",
				scope_hint = nil,
				action = "insert",
				confidence = 0.5,
			}

			local formatted = intent.format(i)

			assert.is_true(formatted:match("auto"))
		end)
	end)
end)
