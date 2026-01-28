---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/core/diff/search_replace.lua

describe("search_replace", function()
	local search_replace = require("codetyper.core.diff.search_replace")

	describe("parse_blocks", function()
		describe("dash style format", function()
			it("should parse dash-style SEARCH/REPLACE blocks", function()
				local response = [[
------- SEARCH
old code
=======
new code
+++++++ REPLACE
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(1, #blocks)
				assert.equals("old code", blocks[1].search)
				assert.equals("new code", blocks[1].replace)
			end)

			it("should parse multiple dash-style blocks", function()
				local response = [[
------- SEARCH
first old
=======
first new
+++++++ REPLACE

------- SEARCH
second old
=======
second new
+++++++ REPLACE
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(2, #blocks)
				assert.equals("first old", blocks[1].search)
				assert.equals("first new", blocks[1].replace)
				assert.equals("second old", blocks[2].search)
				assert.equals("second new", blocks[2].replace)
			end)

			it("should handle multi-line content in dash style", function()
				local response = [[
------- SEARCH
function old()
  return 1
end
=======
function new()
  return 2
end
+++++++ REPLACE
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(1, #blocks)
				assert.is_truthy(blocks[1].search:match("function old"))
				assert.is_truthy(blocks[1].replace:match("function new"))
			end)
		end)

		describe("claude style format", function()
			it("should parse claude-style SEARCH/REPLACE blocks", function()
				local response = [[
<<<<<<< SEARCH
old code
=======
new code
>>>>>>> REPLACE
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(1, #blocks)
				assert.equals("old code", blocks[1].search)
				assert.equals("new code", blocks[1].replace)
			end)

			it("should parse multiple claude-style blocks", function()
				local response = [[
<<<<<<< SEARCH
first old
=======
first new
>>>>>>> REPLACE

<<<<<<< SEARCH
second old
=======
second new
>>>>>>> REPLACE
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(2, #blocks)
			end)
		end)

		describe("simple style format", function()
			it("should parse simple [SEARCH]/[REPLACE]/[END] blocks", function()
				local response = [[
[SEARCH]
old code
[REPLACE]
new code
[END]
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(1, #blocks)
				assert.equals("old code", blocks[1].search)
				assert.equals("new code", blocks[1].replace)
			end)
		end)

		describe("diff block format", function()
			it("should parse markdown diff blocks", function()
				local response = [[
```diff
-old line
+new line
```
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(1, #blocks)
				assert.equals("old line", blocks[1].search)
				assert.equals("new line", blocks[1].replace)
			end)

			it("should handle context lines in diff", function()
				local response = [[
```diff
 context line
-removed line
+added line
 another context
```
]]
				local blocks = search_replace.parse_blocks(response)

				assert.equals(1, #blocks)
				assert.is_truthy(blocks[1].search:match("context line"))
				assert.is_truthy(blocks[1].replace:match("context line"))
			end)
		end)

		describe("edge cases", function()
			it("should return empty array for no blocks", function()
				local response = "Just some text without any SEARCH/REPLACE blocks"
				local blocks = search_replace.parse_blocks(response)

				assert.equals(0, #blocks)
			end)

			it("should handle separator in search content", function()
				-- This is a known limitation - content containing ======= may cause issues
				-- But we should at least not crash
				local response = [[
------- SEARCH
some code
with a line that is just text
=======
new code
+++++++ REPLACE
]]
				local blocks = search_replace.parse_blocks(response)
				-- May or may not parse correctly, but should not error
				assert.is_table(blocks)
			end)
		end)
	end)

	describe("find_match", function()
		it("should find exact match", function()
			local content = "line1\nline2\nline3"
			local match = search_replace.find_match(content, "line2")

			assert.is_truthy(match)
			assert.equals(2, match.start_line)
			assert.equals(2, match.end_line)
		end)

		it("should find multi-line match", function()
			local content = "function test()\n  return 1\nend"
			local match = search_replace.find_match(content, "function test()\n  return 1\nend")

			assert.is_truthy(match)
			assert.equals(1, match.start_line)
			assert.equals(3, match.end_line)
		end)

		it("should return nil for no match", function()
			local content = "line1\nline2\nline3"
			local match = search_replace.find_match(content, "nonexistent")

			assert.is_nil(match)
		end)

		it("should handle empty search", function()
			local content = "some content"
			local match = search_replace.find_match(content, "")

			assert.is_nil(match)
		end)

		it("should handle trailing empty lines in search", function()
			local content = "line1\nline2\nline3"
			local match = search_replace.find_match(content, "line2\n\n")

			assert.is_truthy(match)
			assert.equals(2, match.start_line)
		end)
	end)

	describe("apply_block", function()
		it("should replace matched content", function()
			local content = "line1\nold code\nline3"
			local block = { search = "old code", replace = "new code" }

			local new_content, match, err = search_replace.apply_block(content, block)

			assert.is_truthy(new_content)
			assert.is_truthy(match)
			assert.is_nil(err)
			assert.equals("line1\nnew code\nline3", new_content)
		end)

		it("should preserve indentation", function()
			local content = "function test()\n    old line\nend"
			local block = { search = "    old line", replace = "new line" }

			local new_content = search_replace.apply_block(content, block)

			assert.is_truthy(new_content)
			-- The replacement should get the same indentation as the original
			assert.is_truthy(new_content:match("    new line"))
		end)

		it("should return error for no match", function()
			local content = "line1\nline2\nline3"
			local block = { search = "nonexistent", replace = "new" }

			local new_content, match, err = search_replace.apply_block(content, block)

			assert.is_nil(new_content)
			assert.is_nil(match)
			assert.is_truthy(err)
			assert.is_truthy(err:match("Could not find"))
		end)

		it("should handle multi-line replacement", function()
			local content = "start\nold\nend"
			local block = {
				search = "old",
				replace = "new line 1\nnew line 2",
			}

			local new_content = search_replace.apply_block(content, block)

			assert.is_truthy(new_content:match("new line 1"))
			assert.is_truthy(new_content:match("new line 2"))
		end)
	end)

	describe("apply_blocks", function()
		it("should apply single block", function()
			local content = "line1\nold\nline3"
			local blocks = { { search = "old", replace = "new" } }

			local new_content, results = search_replace.apply_blocks(content, blocks)

			assert.equals("line1\nnew\nline3", new_content)
			assert.equals(1, #results)
			assert.is_true(results[1].success)
		end)

		it("should apply multiple blocks bottom-to-top", function()
			local content = "line1\nold1\nline3\nold2\nline5"
			local blocks = {
				{ search = "old1", replace = "new1" },
				{ search = "old2", replace = "new2" },
			}

			local new_content, results = search_replace.apply_blocks(content, blocks)

			assert.is_truthy(new_content:match("new1"))
			assert.is_truthy(new_content:match("new2"))
			assert.is_true(results[1].success)
			assert.is_true(results[2].success)
		end)

		it("should handle line number changes correctly", function()
			-- This tests the bottom-to-top sorting fix
			-- Block 1 is at line 2, Block 2 is at line 4
			-- If we apply top-to-bottom, adding lines in block 1 would shift block 2
			local content = "line1\nshort\nline3\nshort2\nline5"
			local blocks = {
				{ search = "short", replace = "this is\na much longer\nreplacement" },
				{ search = "short2", replace = "replaced second" },
			}

			local new_content, results = search_replace.apply_blocks(content, blocks)

			-- Both should succeed
			assert.is_true(results[1].success, "First block should succeed")
			assert.is_true(results[2].success, "Second block should succeed")

			-- Both replacements should be present
			assert.is_truthy(new_content:match("a much longer"))
			assert.is_truthy(new_content:match("replaced second"))
		end)

		it("should return results in original order", function()
			local content = "aaa\nbbb\nccc"
			local blocks = {
				{ search = "aaa", replace = "AAA" },
				{ search = "ccc", replace = "CCC" },
			}

			local _, results = search_replace.apply_blocks(content, blocks)

			-- Results should be indexed by original block order
			assert.equals(1, results[1].block_index)
			assert.equals(2, results[2].block_index)
		end)

		it("should handle partial failures", function()
			local content = "line1\nold\nline3"
			local blocks = {
				{ search = "old", replace = "new" },
				{ search = "nonexistent", replace = "fail" },
			}

			local new_content, results = search_replace.apply_blocks(content, blocks)

			assert.is_truthy(new_content:match("new"))
			assert.is_true(results[1].success)
			assert.is_false(results[2].success)
			assert.is_truthy(results[2].error)
		end)

		it("should handle empty blocks array", function()
			local content = "unchanged"
			local blocks = {}

			local new_content, results = search_replace.apply_blocks(content, blocks)

			assert.equals("unchanged", new_content)
			assert.equals(0, #results)
		end)
	end)

	describe("has_blocks", function()
		it("should return true when blocks exist", function()
			local response = [[
------- SEARCH
old
=======
new
+++++++ REPLACE
]]
			assert.is_true(search_replace.has_blocks(response))
		end)

		it("should return false when no blocks", function()
			local response = "Just regular text"
			assert.is_false(search_replace.has_blocks(response))
		end)
	end)
end)
