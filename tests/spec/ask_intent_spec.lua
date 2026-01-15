--- Tests for ask intent detection
local intent = require("codetyper.ask.intent")

describe("ask.intent", function()
	describe("detect", function()
		-- Ask/Explain intent tests
		describe("ask intent", function()
			it("detects 'what' questions as ask", function()
				local result = intent.detect("What does this function do?")
				assert.equals("ask", result.type)
				assert.is_true(result.confidence > 0.3)
			end)

			it("detects 'why' questions as ask", function()
				local result = intent.detect("Why is this variable undefined?")
				assert.equals("ask", result.type)
			end)

			it("detects 'how does' as ask", function()
				local result = intent.detect("How does this algorithm work?")
				assert.is_true(result.type == "ask" or result.type == "explain")
			end)

			it("detects 'explain' requests as explain", function()
				local result = intent.detect("Explain me the project structure")
				assert.equals("explain", result.type)
				assert.is_true(result.confidence > 0.4)
			end)

			it("detects 'walk me through' as explain", function()
				local result = intent.detect("Walk me through this code")
				assert.equals("explain", result.type)
			end)

			it("detects questions ending with ? as likely ask", function()
				local result = intent.detect("Is this the right approach?")
				assert.equals("ask", result.type)
			end)

			it("sets needs_brain_context for ask intent", function()
				local result = intent.detect("What patterns are used here?")
				assert.is_true(result.needs_brain_context)
			end)
		end)

		-- Generate intent tests
		describe("generate intent", function()
			it("detects 'create' commands as generate", function()
				local result = intent.detect("Create a function to sort arrays")
				assert.equals("generate", result.type)
			end)

			it("detects 'write' commands as generate", function()
				local result = intent.detect("Write a unit test for this module")
				-- Could be generate or test
				assert.is_true(result.type == "generate" or result.type == "test")
			end)

			it("detects 'implement' as generate", function()
				local result = intent.detect("Implement a binary search")
				assert.equals("generate", result.type)
				assert.is_true(result.confidence > 0.4)
			end)

			it("detects 'add' commands as generate", function()
				local result = intent.detect("Add error handling to this function")
				assert.equals("generate", result.type)
			end)

			it("detects 'fix' as generate", function()
				local result = intent.detect("Fix the bug in line 42")
				assert.equals("generate", result.type)
			end)
		end)

		-- Refactor intent tests
		describe("refactor intent", function()
			it("detects explicit 'refactor' as refactor", function()
				local result = intent.detect("Refactor this function")
				assert.equals("refactor", result.type)
			end)

			it("detects 'clean up' as refactor", function()
				local result = intent.detect("Clean up this messy code")
				assert.equals("refactor", result.type)
			end)

			it("detects 'simplify' as refactor", function()
				local result = intent.detect("Simplify this logic")
				assert.equals("refactor", result.type)
			end)
		end)

		-- Document intent tests
		describe("document intent", function()
			it("detects 'document' as document", function()
				local result = intent.detect("Document this function")
				assert.equals("document", result.type)
			end)

			it("detects 'add documentation' as document", function()
				local result = intent.detect("Add documentation to this class")
				assert.equals("document", result.type)
			end)

			it("detects 'add jsdoc' as document", function()
				local result = intent.detect("Add jsdoc comments")
				assert.equals("document", result.type)
			end)
		end)

		-- Test intent tests
		describe("test intent", function()
			it("detects 'write tests for' as test", function()
				local result = intent.detect("Write tests for this module")
				assert.equals("test", result.type)
			end)

			it("detects 'add unit tests' as test", function()
				local result = intent.detect("Add unit tests for the parser")
				assert.equals("test", result.type)
			end)

			it("detects 'generate tests' as test", function()
				local result = intent.detect("Generate tests for the API")
				assert.equals("test", result.type)
			end)
		end)

		-- Project context tests
		describe("project context detection", function()
			it("detects 'project' as needing project context", function()
				local result = intent.detect("Explain the project architecture")
				assert.is_true(result.needs_project_context)
			end)

			it("detects 'codebase' as needing project context", function()
				local result = intent.detect("How is the codebase organized?")
				assert.is_true(result.needs_project_context)
			end)

			it("does not need project context for simple questions", function()
				local result = intent.detect("What does this variable mean?")
				assert.is_false(result.needs_project_context)
			end)
		end)

		-- Exploration tests
		describe("exploration detection", function()
			it("detects 'explain me the project' as needing exploration", function()
				local result = intent.detect("Explain me the project")
				assert.is_true(result.needs_exploration)
			end)

			it("detects 'explain the codebase' as needing exploration", function()
				local result = intent.detect("Explain the codebase structure")
				assert.is_true(result.needs_exploration)
			end)

			it("detects 'explore project' as needing exploration", function()
				local result = intent.detect("Explore this project")
				assert.is_true(result.needs_exploration)
			end)

			it("does not need exploration for simple questions", function()
				local result = intent.detect("What does this function do?")
				assert.is_false(result.needs_exploration)
			end)
		end)
	end)

	describe("get_prompt_type", function()
		it("maps ask to ask", function()
			local result = intent.get_prompt_type({ type = "ask" })
			assert.equals("ask", result)
		end)

		it("maps explain to ask", function()
			local result = intent.get_prompt_type({ type = "explain" })
			assert.equals("ask", result)
		end)

		it("maps generate to code_generation", function()
			local result = intent.get_prompt_type({ type = "generate" })
			assert.equals("code_generation", result)
		end)

		it("maps refactor to refactor", function()
			local result = intent.get_prompt_type({ type = "refactor" })
			assert.equals("refactor", result)
		end)

		it("maps document to document", function()
			local result = intent.get_prompt_type({ type = "document" })
			assert.equals("document", result)
		end)

		it("maps test to test", function()
			local result = intent.get_prompt_type({ type = "test" })
			assert.equals("test", result)
		end)
	end)

	describe("produces_code", function()
		it("returns false for ask", function()
			assert.is_false(intent.produces_code({ type = "ask" }))
		end)

		it("returns false for explain", function()
			assert.is_false(intent.produces_code({ type = "explain" }))
		end)

		it("returns true for generate", function()
			assert.is_true(intent.produces_code({ type = "generate" }))
		end)

		it("returns true for refactor", function()
			assert.is_true(intent.produces_code({ type = "refactor" }))
		end)

		it("returns true for document", function()
			assert.is_true(intent.produces_code({ type = "document" }))
		end)

		it("returns true for test", function()
			assert.is_true(intent.produces_code({ type = "test" }))
		end)
	end)
end)
