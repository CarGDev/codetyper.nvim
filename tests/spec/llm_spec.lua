---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/llm/init.lua

describe("llm", function()
	local llm = require("codetyper.llm")

	describe("extract_code", function()
		it("should extract code from markdown code block", function()
			local response = [[
Here is the code:

```lua
function hello()
  print("Hello!")
end
```

That should work.
]]
			local code = llm.extract_code(response)

			assert.is_true(code:match("function hello"))
			assert.is_true(code:match('print%("Hello!"%)'))
			assert.is_false(code:match("```"))
			assert.is_false(code:match("Here is the code"))
		end)

		it("should extract code from generic code block", function()
			local response = [[
```
const x = 1;
const y = 2;
```
]]
			local code = llm.extract_code(response)

			assert.is_true(code:match("const x = 1"))
		end)

		it("should handle multiple code blocks (return first)", function()
			local response = [[
```javascript
const first = true;
```

```javascript
const second = true;
```
]]
			local code = llm.extract_code(response)

			assert.is_true(code:match("first"))
		end)

		it("should return original if no code blocks", function()
			local response = "function test() return true end"
			local code = llm.extract_code(response)

			assert.equals(response, code)
		end)

		it("should handle empty code blocks", function()
			local response = [[
```
```
]]
			local code = llm.extract_code(response)

			assert.equals("", vim.trim(code))
		end)

		it("should preserve indentation in extracted code", function()
			local response = [[
```lua
function test()
  if true then
    print("nested")
  end
end
```
]]
			local code = llm.extract_code(response)

			assert.is_true(code:match("  if true then"))
			assert.is_true(code:match("    print"))
		end)
	end)

	describe("get_client", function()
		it("should return a client with generate function", function()
			-- This test depends on config, but verifies interface
			local client = llm.get_client()

			assert.is_table(client)
			assert.is_function(client.generate)
		end)
	end)

	describe("build_system_prompt", function()
		it("should include language context when provided", function()
			local context = {
				language = "typescript",
				file_path = "/test/file.ts",
			}

			local prompt = llm.build_system_prompt(context)

			assert.is_true(prompt:match("typescript") or prompt:match("TypeScript"))
		end)

		it("should work with minimal context", function()
			local prompt = llm.build_system_prompt({})

			assert.is_string(prompt)
			assert.is_true(#prompt > 0)
		end)
	end)
end)
