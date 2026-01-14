---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/utils.lua

describe("utils", function()
	local utils = require("codetyper.utils")

	describe("is_coder_file", function()
		it("should return true for coder files", function()
			assert.is_true(utils.is_coder_file("index.coder.ts"))
			assert.is_true(utils.is_coder_file("main.coder.lua"))
			assert.is_true(utils.is_coder_file("/path/to/file.coder.py"))
		end)

		it("should return false for regular files", function()
			assert.is_false(utils.is_coder_file("index.ts"))
			assert.is_false(utils.is_coder_file("main.lua"))
			assert.is_false(utils.is_coder_file("coder.ts"))
		end)
	end)

	describe("get_target_path", function()
		it("should convert coder path to target path", function()
			assert.equals("index.ts", utils.get_target_path("index.coder.ts"))
			assert.equals("main.lua", utils.get_target_path("main.coder.lua"))
			assert.equals("/path/to/file.py", utils.get_target_path("/path/to/file.coder.py"))
		end)
	end)

	describe("get_coder_path", function()
		it("should convert target path to coder path", function()
			assert.equals("index.coder.ts", utils.get_coder_path("index.ts"))
			assert.equals("main.coder.lua", utils.get_coder_path("main.lua"))
		end)

		it("should preserve directory path", function()
			local result = utils.get_coder_path("/path/to/file.py")
			assert.is_truthy(result:match("/path/to/"))
			assert.is_truthy(result:match("file%.coder%.py"))
		end)
	end)

	describe("escape_pattern", function()
		it("should escape special pattern characters", function()
			-- Note: @ is NOT a special Lua pattern character
			-- Special chars are: ( ) . % + - * ? [ ] ^ $
			assert.equals("/@", utils.escape_pattern("/@"))
			assert.equals("@/", utils.escape_pattern("@/"))
			assert.equals("hello%.world", utils.escape_pattern("hello.world"))
			assert.equals("test%+pattern", utils.escape_pattern("test+pattern"))
		end)

		it("should handle multiple special characters", function()
			local input = "(test)[pattern]"
			local escaped = utils.escape_pattern(input)
			-- Use string.find with plain=true to avoid pattern interpretation
			assert.is_truthy(string.find(escaped, "%(", 1, true))
			assert.is_truthy(string.find(escaped, "%)", 1, true))
			assert.is_truthy(string.find(escaped, "%[", 1, true))
			assert.is_truthy(string.find(escaped, "%]", 1, true))
		end)
	end)

	describe("file operations", function()
		local test_dir
		local test_file

		before_each(function()
			test_dir = vim.fn.tempname()
			utils.ensure_dir(test_dir)
			test_file = test_dir .. "/test.txt"
		end)

		after_each(function()
			vim.fn.delete(test_dir, "rf")
		end)

		describe("ensure_dir", function()
			it("should create directory", function()
				local new_dir = test_dir .. "/subdir"
				local result = utils.ensure_dir(new_dir)

				assert.is_true(result)
				assert.equals(1, vim.fn.isdirectory(new_dir))
			end)

			it("should return true for existing directory", function()
				local result = utils.ensure_dir(test_dir)
				assert.is_true(result)
			end)
		end)

		describe("write_file", function()
			it("should write content to file", function()
				local result = utils.write_file(test_file, "test content")

				assert.is_true(result)
				assert.is_true(utils.file_exists(test_file))
			end)
		end)

		describe("read_file", function()
			it("should read file content", function()
				utils.write_file(test_file, "test content")

				local content = utils.read_file(test_file)

				assert.equals("test content", content)
			end)

			it("should return nil for non-existent file", function()
				local content = utils.read_file("/non/existent/file.txt")
				assert.is_nil(content)
			end)
		end)

		describe("file_exists", function()
			it("should return true for existing file", function()
				utils.write_file(test_file, "content")
				assert.is_true(utils.file_exists(test_file))
			end)

			it("should return false for non-existent file", function()
				assert.is_false(utils.file_exists("/non/existent/file.txt"))
			end)
		end)
	end)

	describe("get_filetype", function()
		it("should return filetype for buffer", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.bo[buf].filetype = "lua"

			local ft = utils.get_filetype(buf)

			assert.equals("lua", ft)
			vim.api.nvim_buf_delete(buf, { force = true })
		end)
	end)
end)
