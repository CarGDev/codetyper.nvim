---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/parser.lua

describe("parser", function()
	local parser = require("codetyper.parser")

	describe("find_prompts", function()
		it("should find single-line prompt", function()
			local content = "/@ create a function @/"
			local prompts = parser.find_prompts(content, "/@", "@/")

			assert.equals(1, #prompts)
			assert.equals(" create a function ", prompts[1].content)
			assert.equals(1, prompts[1].start_line)
			assert.equals(1, prompts[1].end_line)
		end)

		it("should find multi-line prompt", function()
			local content = [[
/@ create a function
that validates email
addresses @/
]]
			local prompts = parser.find_prompts(content, "/@", "@/")

			assert.equals(1, #prompts)
			assert.is_true(prompts[1].content:match("validates email"))
			assert.equals(2, prompts[1].start_line)
			assert.equals(4, prompts[1].end_line)
		end)

		it("should find multiple prompts", function()
			local content = [[
/@ first prompt @/
some code here
/@ second prompt @/
more code
/@ third prompt
multiline @/
]]
			local prompts = parser.find_prompts(content, "/@", "@/")

			assert.equals(3, #prompts)
			assert.equals(" first prompt ", prompts[1].content)
			assert.equals(" second prompt ", prompts[2].content)
			assert.is_true(prompts[3].content:match("third prompt"))
		end)

		it("should return empty table when no prompts found", function()
			local content = "just some regular code\nno prompts here"
			local prompts = parser.find_prompts(content, "/@", "@/")

			assert.equals(0, #prompts)
		end)

		it("should handle prompts with special characters", function()
			local content = "/@ add (function) with [brackets] @/"
			local prompts = parser.find_prompts(content, "/@", "@/")

			assert.equals(1, #prompts)
			assert.is_true(prompts[1].content:match("function"))
			assert.is_true(prompts[1].content:match("brackets"))
		end)

		it("should handle empty prompt content", function()
			local content = "/@  @/"
			local prompts = parser.find_prompts(content, "/@", "@/")

			assert.equals(1, #prompts)
			assert.equals("  ", prompts[1].content)
		end)

		it("should handle custom tags", function()
			local content = "<!-- prompt: create button -->"
			local prompts = parser.find_prompts(content, "<!-- prompt:", "-->")

			assert.equals(1, #prompts)
			assert.is_true(prompts[1].content:match("create button"))
		end)
	end)

	describe("detect_prompt_type", function()
		it("should detect refactor type", function()
			assert.equals("refactor", parser.detect_prompt_type("refactor this code"))
			assert.equals("refactor", parser.detect_prompt_type("REFACTOR the function"))
		end)

		it("should detect add type", function()
			assert.equals("add", parser.detect_prompt_type("add a new function"))
			assert.equals("add", parser.detect_prompt_type("create a component"))
			assert.equals("add", parser.detect_prompt_type("implement sorting algorithm"))
		end)

		it("should detect document type", function()
			assert.equals("document", parser.detect_prompt_type("document this function"))
			assert.equals("document", parser.detect_prompt_type("add jsdoc comments"))
			assert.equals("document", parser.detect_prompt_type("comment the code"))
		end)

		it("should detect explain type", function()
			assert.equals("explain", parser.detect_prompt_type("explain this code"))
			assert.equals("explain", parser.detect_prompt_type("what does this do"))
			assert.equals("explain", parser.detect_prompt_type("how does this work"))
		end)

		it("should return generic for unknown types", function()
			assert.equals("generic", parser.detect_prompt_type("do something"))
			assert.equals("generic", parser.detect_prompt_type("make it better"))
		end)
	end)

	describe("clean_prompt", function()
		it("should trim whitespace", function()
			assert.equals("hello", parser.clean_prompt("  hello  "))
			assert.equals("hello", parser.clean_prompt("\n\nhello\n\n"))
		end)

		it("should normalize multiple newlines", function()
			local input = "line1\n\n\n\nline2"
			local expected = "line1\n\nline2"
			assert.equals(expected, parser.clean_prompt(input))
		end)

		it("should preserve single newlines", function()
			local input = "line1\nline2\nline3"
			assert.equals(input, parser.clean_prompt(input))
		end)
	end)

	describe("has_closing_tag", function()
		it("should return true when closing tag exists", function()
			assert.is_true(parser.has_closing_tag("some text @/", "@/"))
			assert.is_true(parser.has_closing_tag("@/", "@/"))
		end)

		it("should return false when closing tag missing", function()
			assert.is_false(parser.has_closing_tag("some text", "@/"))
			assert.is_false(parser.has_closing_tag("", "@/"))
		end)
	end)

	describe("extract_file_references", function()
		it("should extract single file reference", function()
			local files = parser.extract_file_references("fix this @utils.ts")
			assert.equals(1, #files)
			assert.equals("utils.ts", files[1])
		end)

		it("should extract multiple file references", function()
			local files = parser.extract_file_references("use @config.ts and @helpers.lua")
			assert.equals(2, #files)
			assert.equals("config.ts", files[1])
			assert.equals("helpers.lua", files[2])
		end)

		it("should extract file paths with directories", function()
			local files = parser.extract_file_references("check @src/utils/helpers.ts")
			assert.equals(1, #files)
			assert.equals("src/utils/helpers.ts", files[1])
		end)

		it("should NOT extract closing tag @/", function()
			local files = parser.extract_file_references("fix this @/")
			assert.equals(0, #files)
		end)

		it("should handle mixed content with closing tag", function()
			local files = parser.extract_file_references("use @config.ts to fix @/")
			assert.equals(1, #files)
			assert.equals("config.ts", files[1])
		end)

		it("should return empty table when no file refs", function()
			local files = parser.extract_file_references("just some text")
			assert.equals(0, #files)
		end)

		it("should handle relative paths", function()
			local files = parser.extract_file_references("check @../config.json")
			assert.equals(1, #files)
			assert.equals("../config.json", files[1])
		end)
	end)

	describe("strip_file_references", function()
		it("should remove single file reference", function()
			local result = parser.strip_file_references("fix this @utils.ts please")
			assert.equals("fix this  please", result)
		end)

		it("should remove multiple file references", function()
			local result = parser.strip_file_references("use @config.ts and @helpers.lua")
			assert.equals("use  and ", result)
		end)

		it("should NOT remove closing tag", function()
			local result = parser.strip_file_references("fix this @/")
			-- @/ should remain since it's the closing tag pattern
			assert.is_true(result:find("@/") ~= nil)
		end)

		it("should handle paths with directories", function()
			local result = parser.strip_file_references("check @src/utils.ts here")
			assert.equals("check  here", result)
		end)
	end)
end)
