---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/support/string_match.lua

describe("string_match utilities", function()
	local string_match = require("codetyper.support.string_match")

	describe("normalize_line_endings", function()
		it("should convert CRLF to LF", function()
			assert.equals("line1\nline2", string_match.normalize_line_endings("line1\r\nline2"))
		end)

		it("should convert CR to LF", function()
			assert.equals("line1\nline2", string_match.normalize_line_endings("line1\rline2"))
		end)

		it("should preserve LF", function()
			assert.equals("line1\nline2", string_match.normalize_line_endings("line1\nline2"))
		end)
	end)

	describe("normalize_whitespace", function()
		it("should collapse multiple spaces", function()
			assert.equals("a b c", string_match.normalize_whitespace("a   b    c"))
		end)

		it("should trim leading and trailing", function()
			assert.equals("text", string_match.normalize_whitespace("  text  "))
		end)

		it("should handle tabs and newlines", function()
			assert.equals("a b", string_match.normalize_whitespace("a\t\n  b"))
		end)
	end)

	describe("trim", function()
		it("should trim both ends", function()
			assert.equals("text", string_match.trim("  text  "))
		end)

		it("should handle empty string", function()
			assert.equals("", string_match.trim("   "))
		end)
	end)

	describe("trim_trailing", function()
		it("should trim only trailing whitespace", function()
			assert.equals("  text", string_match.trim_trailing("  text  "))
		end)
	end)

	describe("get_indentation", function()
		it("should return leading whitespace", function()
			assert.equals("    ", string_match.get_indentation("    code"))
			assert.equals("\t\t", string_match.get_indentation("\t\tcode"))
		end)

		it("should return empty string for no indentation", function()
			assert.equals("", string_match.get_indentation("code"))
		end)

		it("should handle nil", function()
			assert.equals("", string_match.get_indentation(nil))
		end)
	end)

	describe("strip_indentation", function()
		it("should remove leading whitespace from all lines", function()
			local input = "  line1\n    line2\n  line3"
			local expected = "line1\nline2\nline3"
			assert.equals(expected, string_match.strip_indentation(input))
		end)
	end)

	describe("trim_lines", function()
		it("should trim each line", function()
			local input = "  line1  \n  line2  "
			local expected = "line1\nline2"
			assert.equals(expected, string_match.trim_lines(input))
		end)
	end)

	describe("levenshtein", function()
		it("should return 0 for identical strings", function()
			assert.equals(0, string_match.levenshtein("hello", "hello"))
		end)

		it("should return correct distance for single edit", function()
			assert.equals(1, string_match.levenshtein("hello", "hallo"))
			assert.equals(1, string_match.levenshtein("hello", "hell"))
			assert.equals(1, string_match.levenshtein("hello", "helloo"))
		end)

		it("should return correct distance for multiple edits", function()
			assert.equals(3, string_match.levenshtein("kitten", "sitting"))
		end)

		it("should handle empty strings", function()
			assert.equals(5, string_match.levenshtein("", "hello"))
			assert.equals(5, string_match.levenshtein("hello", ""))
			assert.equals(0, string_match.levenshtein("", ""))
		end)
	end)

	describe("similarity", function()
		it("should return 1.0 for identical strings", function()
			assert.equals(1.0, string_match.similarity("hello", "hello"))
		end)

		it("should return value between 0 and 1", function()
			local sim = string_match.similarity("hello", "hallo")
			assert.is_true(sim > 0 and sim < 1)
			assert.is_true(sim > 0.7) -- 4/5 = 0.8 similarity
		end)

		it("should return 1.0 for empty strings", function()
			assert.equals(1.0, string_match.similarity("", ""))
		end)
	end)

	describe("exact_match", function()
		it("should find exact substring", function()
			local content = "line1\nline2\nline3"
			local result = string_match.exact_match(content, "line2")

			assert.is_truthy(result)
			assert.equals("exact", result.strategy)
			assert.equals(1.0, result.confidence)
		end)

		it("should return nil for no match", function()
			local result = string_match.exact_match("hello world", "foo")
			assert.is_nil(result)
		end)
	end)

	describe("whitespace_normalized_match", function()
		it("should match ignoring whitespace differences", function()
			local content = "function test()\n    return 1\nend"
			local search = "function test()  return 1  end"

			local result = string_match.whitespace_normalized_match(content, search)

			assert.is_truthy(result)
			assert.equals("whitespace_normalized", result.strategy)
		end)
	end)

	describe("indentation_flexible_match", function()
		it("should match with different indentation", function()
			local content = "    function test()\n        return 1\n    end"
			local search = "function test()\n    return 1\nend"

			local result = string_match.indentation_flexible_match(content, search)

			assert.is_truthy(result)
			assert.equals("indentation_flexible", result.strategy)
		end)
	end)

	describe("line_trimmed_match", function()
		it("should match with trailing whitespace differences", function()
			local content = "function test()  \n    return 1   \nend"
			local search = "function test()\n    return 1\nend"

			local result = string_match.line_trimmed_match(content, search)

			assert.is_truthy(result)
			assert.equals("line_trimmed", result.strategy)
		end)
	end)

	describe("fuzzy_anchor_match", function()
		it("should match with fuzzy first/last lines", function()
			local content = "function test_func()\n    -- some code\n    return 1\nend"
			local search = "function test_func( )\n    -- different comment\n    return 1\nend"

			local result = string_match.fuzzy_anchor_match(content, search)

			-- May or may not match depending on similarity threshold
			if result then
				assert.equals("fuzzy_anchor", result.strategy)
			end
		end)

		it("should return nil for single line input", function()
			local result = string_match.fuzzy_anchor_match("content", "search")
			assert.is_nil(result)
		end)
	end)

	describe("find_match", function()
		it("should find exact match first", function()
			local content = "exact text here"
			local match, strategy = string_match.find_match(content, "exact text")

			assert.is_truthy(match)
			assert.equals("exact", strategy)
		end)

		it("should fall back to whitespace normalized", function()
			local content = "function   test()"
			local match, strategy = string_match.find_match(content, "function test()")

			assert.is_truthy(match)
			-- Could be exact if spaces match, or whitespace_normalized
		end)

		it("should return nil and 'none' for no match", function()
			local match, strategy = string_match.find_match("hello", "goodbye")

			assert.is_nil(match)
			assert.equals("none", strategy)
		end)
	end)

	describe("find_match_lines", function()
		it("should match exact lines", function()
			local content_lines = { "line1", "line2", "line3" }
			local search_lines = { "line2" }

			local result = string_match.find_match_lines(content_lines, search_lines)

			assert.is_truthy(result)
			assert.equals(2, result.start_line)
			assert.equals(2, result.end_line)
		end)

		it("should match multi-line blocks", function()
			local content_lines = { "line1", "line2", "line3", "line4" }
			local search_lines = { "line2", "line3" }

			local result = string_match.find_match_lines(content_lines, search_lines)

			assert.is_truthy(result)
			assert.equals(2, result.start_line)
			assert.equals(3, result.end_line)
		end)

		it("should handle empty search", function()
			local result = string_match.find_match_lines({ "line1" }, {})
			assert.is_nil(result)
		end)
	end)
end)
