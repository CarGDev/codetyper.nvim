---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/support/path.lua

describe("path utilities", function()
	local path_utils = require("codetyper.support.path")
	local test_dir

	before_each(function()
		test_dir = vim.fn.tempname()
		vim.fn.mkdir(test_dir, "p")
	end)

	after_each(function()
		vim.fn.delete(test_dir, "rf")
	end)

	describe("resolve", function()
		it("should return absolute path as-is", function()
			assert.equals("/absolute/path", path_utils.resolve("/absolute/path"))
		end)

		it("should resolve relative path from cwd", function()
			local cwd = vim.fn.getcwd()
			local result = path_utils.resolve("relative/path")
			assert.equals(cwd .. "/relative/path", result)
		end)

		it("should resolve relative path from custom base", function()
			local result = path_utils.resolve("file.txt", "/custom/base")
			assert.equals("/custom/base/file.txt", result)
		end)

		it("should handle empty path", function()
			assert.equals("", path_utils.resolve(""))
			assert.equals("", path_utils.resolve(nil))
		end)
	end)

	describe("is_absolute", function()
		it("should return true for absolute paths", function()
			assert.is_true(path_utils.is_absolute("/absolute/path"))
			assert.is_true(path_utils.is_absolute("/"))
		end)

		it("should return false for relative paths", function()
			assert.is_false(path_utils.is_absolute("relative/path"))
			assert.is_false(path_utils.is_absolute("file.txt"))
		end)

		it("should handle nil and empty string", function()
			assert.is_false(path_utils.is_absolute(nil))
			assert.is_false(path_utils.is_absolute(""))
		end)
	end)

	describe("make_relative", function()
		it("should make path relative to base", function()
			local result = path_utils.make_relative("/base/dir/file.txt", "/base/dir")
			assert.equals("file.txt", result)
		end)

		it("should return original if not under base", function()
			local result = path_utils.make_relative("/other/path/file.txt", "/base/dir")
			assert.equals("/other/path/file.txt", result)
		end)
	end)

	describe("exists", function()
		it("should return true for existing directory", function()
			assert.is_true(path_utils.exists(test_dir))
		end)

		it("should return true for existing file", function()
			local file = test_dir .. "/test.txt"
			vim.fn.writefile({ "content" }, file)
			assert.is_true(path_utils.exists(file))
		end)

		it("should return false for non-existent path", function()
			assert.is_false(path_utils.exists("/non/existent/path"))
		end)
	end)

	describe("is_file", function()
		it("should return true for files", function()
			local file = test_dir .. "/test.txt"
			vim.fn.writefile({ "content" }, file)
			assert.is_true(path_utils.is_file(file))
		end)

		it("should return false for directories", function()
			assert.is_false(path_utils.is_file(test_dir))
		end)
	end)

	describe("is_directory", function()
		it("should return true for directories", function()
			assert.is_true(path_utils.is_directory(test_dir))
		end)

		it("should return false for files", function()
			local file = test_dir .. "/test.txt"
			vim.fn.writefile({ "content" }, file)
			assert.is_false(path_utils.is_directory(file))
		end)
	end)

	describe("parent", function()
		it("should return parent directory", function()
			assert.equals("/path/to", path_utils.parent("/path/to/file.txt"))
			assert.equals("/path", path_utils.parent("/path/to"))
		end)
	end)

	describe("filename", function()
		it("should return filename", function()
			assert.equals("file.txt", path_utils.filename("/path/to/file.txt"))
		end)
	end)

	describe("extension", function()
		it("should return file extension", function()
			assert.equals("txt", path_utils.extension("/path/to/file.txt"))
			assert.equals("lua", path_utils.extension("test.lua"))
		end)
	end)

	describe("ensure_parent_dir", function()
		it("should create parent directory if missing", function()
			local file = test_dir .. "/subdir/deep/file.txt"
			local result = path_utils.ensure_parent_dir(file)

			assert.is_true(result)
			assert.equals(1, vim.fn.isdirectory(test_dir .. "/subdir/deep"))
		end)

		it("should return true if parent already exists", function()
			local file = test_dir .. "/file.txt"
			local result = path_utils.ensure_parent_dir(file)
			assert.is_true(result)
		end)
	end)

	describe("normalize", function()
		it("should remove double slashes", function()
			assert.equals("/path/to/file", path_utils.normalize("/path//to//file"))
		end)

		it("should remove trailing slash", function()
			assert.equals("/path/to/dir", path_utils.normalize("/path/to/dir/"))
		end)

		it("should preserve root slash", function()
			assert.equals("/", path_utils.normalize("/"))
		end)
	end)

	describe("join", function()
		it("should join path components", function()
			assert.equals("/path/to/file", path_utils.join("/path", "to", "file"))
		end)

		it("should normalize the result", function()
			assert.equals("/path/to/file", path_utils.join("/path/", "/to/", "file"))
		end)
	end)
end)
