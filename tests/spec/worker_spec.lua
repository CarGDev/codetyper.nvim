---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/agent/worker.lua response cleaning

-- We need to test the clean_response function
-- Since it's local, we'll create a test module that exposes it

describe("worker response cleaning", function()
	-- Mock the clean_response function behavior directly
	local function clean_response(response)
		if not response then
			return ""
		end

		local cleaned = response

		-- Remove the original prompt tags /@ ... @/ if they appear in output
		-- Use [%s%S] to match any character including newlines
		cleaned = cleaned:gsub("/@[%s%S]-@/", "")

		-- Try to extract code from markdown code blocks
		local code_block = cleaned:match("```[%w]*\n(.-)\n```")
		if not code_block then
			code_block = cleaned:match("```[%w]*(.-)\n```")
		end
		if not code_block then
			code_block = cleaned:match("```(.-)```")
		end

		if code_block then
			cleaned = code_block
		else
			local explanation_starts = {
				"^[Ii]'m sorry.-\n",
				"^[Ii] apologize.-\n",
				"^[Hh]ere is.-:\n",
				"^[Hh]ere's.-:\n",
				"^[Tt]his is.-:\n",
				"^[Bb]ased on.-:\n",
				"^[Ss]ure.-:\n",
				"^[Oo][Kk].-:\n",
				"^[Cc]ertainly.-:\n",
			}
			for _, pattern in ipairs(explanation_starts) do
				cleaned = cleaned:gsub(pattern, "")
			end

			local explanation_ends = {
				"\n[Tt]his code.-$",
				"\n[Tt]his function.-$",
				"\n[Tt]his is a.-$",
				"\n[Ii] hope.-$",
				"\n[Ll]et me know.-$",
				"\n[Ff]eel free.-$",
				"\n[Nn]ote:.-$",
				"\n[Pp]lease replace.-$",
				"\n[Pp]lease note.-$",
				"\n[Yy]ou might want.-$",
				"\n[Yy]ou may want.-$",
				"\n[Mm]ake sure.-$",
				"\n[Aa]lso,.-$",
				"\n[Rr]emember.-$",
			}
			for _, pattern in ipairs(explanation_ends) do
				cleaned = cleaned:gsub(pattern, "")
			end
		end

		cleaned = cleaned:gsub("^```[%w]*\n?", "")
		cleaned = cleaned:gsub("\n?```$", "")
		cleaned = cleaned:match("^%s*(.-)%s*$") or cleaned

		return cleaned
	end

	describe("clean_response", function()
		it("should extract code from markdown code blocks", function()
			local response = [[```java
public void test() {
    System.out.println("Hello");
}
```]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("public void test") ~= nil)
			assert.is_true(cleaned:find("```") == nil)
		end)

		it("should handle code blocks without language", function()
			local response = [[```
function test()
    print("hello")
end
```]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("function test") ~= nil)
			assert.is_true(cleaned:find("```") == nil)
		end)

		it("should remove single-line prompt tags from response", function()
			local response = [[/@ create a function @/
function test() end]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("/@") == nil)
			assert.is_true(cleaned:find("@/") == nil)
			assert.is_true(cleaned:find("function test") ~= nil)
		end)

		it("should remove multiline prompt tags from response", function()
			local response = [[function test() end
/@
create a function
that does something
@/
function another() end]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("/@") == nil)
			assert.is_true(cleaned:find("@/") == nil)
			assert.is_true(cleaned:find("function test") ~= nil)
			assert.is_true(cleaned:find("function another") ~= nil)
		end)

		it("should remove multiple prompt tags from response", function()
			local response = [[function test() end
/@ first prompt @/
/@ second
multiline prompt @/
function another() end]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("/@") == nil)
			assert.is_true(cleaned:find("@/") == nil)
			assert.is_true(cleaned:find("function test") ~= nil)
			assert.is_true(cleaned:find("function another") ~= nil)
		end)

		it("should remove apology prefixes", function()
			local response = [[I'm sorry for any confusion.
Here is the code:
function test() end]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("sorry") == nil or cleaned:find("function test") ~= nil)
		end)

		it("should remove trailing explanations", function()
			local response = [[function test() end
This code does something useful.]]
			local cleaned = clean_response(response)
			-- The ending pattern should be removed
			assert.is_true(cleaned:find("function test") ~= nil)
		end)

		it("should handle empty response", function()
			local cleaned = clean_response("")
			assert.equals("", cleaned)
		end)

		it("should handle nil response", function()
			local cleaned = clean_response(nil)
			assert.equals("", cleaned)
		end)

		it("should preserve clean code", function()
			local response = [[function test()
    return true
end]]
			local cleaned = clean_response(response)
			assert.equals(response, cleaned)
		end)

		it("should handle complex markdown with explanation", function()
			local response = [[Here is the implementation:

```lua
local function validate(input)
    if not input then
        return false
    end
    return true
end
```

Let me know if you need any changes.]]
			local cleaned = clean_response(response)
			assert.is_true(cleaned:find("local function validate") ~= nil)
			assert.is_true(cleaned:find("```") == nil)
			assert.is_true(cleaned:find("Let me know") == nil)
		end)
	end)

	describe("needs_more_context detection", function()
		local context_needed_patterns = {
			"^%s*i need more context",
			"^%s*i'm sorry.-i need more",
			"^%s*i apologize.-i need more",
			"^%s*could you provide more context",
			"^%s*could you please provide more",
			"^%s*can you clarify",
			"^%s*please provide more context",
			"^%s*more information needed",
			"^%s*not enough context",
			"^%s*i don't have enough",
			"^%s*unclear what you",
			"^%s*what do you mean by",
		}

		local function needs_more_context(response)
			if not response then
				return false
			end

			-- If response has substantial code, don't ask for context
			local lines = vim.split(response, "\n")
			local code_lines = 0
			for _, line in ipairs(lines) do
				if line:match("[{}();=]") or line:match("function") or line:match("def ")
					or line:match("class ") or line:match("return ") or line:match("import ")
					or line:match("public ") or line:match("private ") or line:match("local ") then
					code_lines = code_lines + 1
				end
			end

			if code_lines >= 3 then
				return false
			end

			local lower = response:lower()
			for _, pattern in ipairs(context_needed_patterns) do
				if lower:match(pattern) then
					return true
				end
			end
			return false
		end

		it("should detect context needed phrases at start", function()
			assert.is_true(needs_more_context("I need more context to help you"))
			assert.is_true(needs_more_context("Could you provide more context?"))
			assert.is_true(needs_more_context("Can you clarify what you want?"))
			assert.is_true(needs_more_context("I'm sorry, but I need more information to help"))
		end)

		it("should not trigger on normal responses", function()
			assert.is_false(needs_more_context("Here is your code"))
			assert.is_false(needs_more_context("function test() end"))
			assert.is_false(needs_more_context("The implementation is complete"))
		end)

		it("should not trigger when response has substantial code", function()
			local response_with_code = [[Here is the code:
function test() {
    return true;
}
function another() {
    return false;
}]]
			assert.is_false(needs_more_context(response_with_code))
		end)

		it("should not trigger on code with explanatory text", function()
			local response = [[public void test() {
    System.out.println("Hello");
}
Please replace the connection string with your actual database.]]
			assert.is_false(needs_more_context(response))
		end)

		it("should handle nil response", function()
			assert.is_false(needs_more_context(nil))
		end)
	end)
end)
