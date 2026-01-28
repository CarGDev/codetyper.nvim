---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/core/tools/common.lua

describe("tools common utilities", function()
	local common = require("codetyper.core.tools.common")

	describe("validate_required", function()
		it("should return true when all required params present", function()
			local input = { path = "/test", content = "data" }
			local valid, err = common.validate_required(input, { "path", "content" })

			assert.is_true(valid)
			assert.is_nil(err)
		end)

		it("should return false when required param missing", function()
			local input = { path = "/test" }
			local valid, err = common.validate_required(input, { "path", "content" })

			assert.is_false(valid)
			assert.equals("content is required", err)
		end)

		it("should handle empty required list", function()
			local valid, err = common.validate_required({}, {})

			assert.is_true(valid)
			assert.is_nil(err)
		end)

		it("should detect nil values", function()
			local input = { path = nil }
			local valid, err = common.validate_required(input, { "path" })

			assert.is_false(valid)
			assert.equals("path is required", err)
		end)
	end)

	describe("log", function()
		it("should call on_log when provided", function()
			local logged_message = nil
			local opts = {
				on_log = function(msg)
					logged_message = msg
				end,
			}

			common.log(opts, "test message")

			assert.equals("test message", logged_message)
		end)

		it("should not error when on_log missing", function()
			local opts = {}
			assert.has_no.errors(function()
				common.log(opts, "test message")
			end)
		end)
	end)

	describe("complete", function()
		it("should call on_complete when provided", function()
			local completed_result = nil
			local completed_error = nil
			local opts = {
				on_complete = function(result, err)
					completed_result = result
					completed_error = err
				end,
			}

			common.complete(opts, "result", "error")

			assert.equals("result", completed_result)
			assert.equals("error", completed_error)
		end)

		it("should not error when on_complete missing", function()
			local opts = {}
			assert.has_no.errors(function()
				common.complete(opts, "result", nil)
			end)
		end)
	end)

	describe("return_result", function()
		it("should invoke callback and return values", function()
			local callback_called = false
			local opts = {
				on_complete = function()
					callback_called = true
				end,
			}

			local result, err = common.return_result(opts, "data", nil)

			assert.is_true(callback_called)
			assert.equals("data", result)
			assert.is_nil(err)
		end)

		it("should return error when provided", function()
			local opts = {}
			local result, err = common.return_result(opts, nil, "error msg")

			assert.is_nil(result)
			assert.equals("error msg", err)
		end)
	end)

	describe("json_result", function()
		it("should encode table to JSON", function()
			local data = { key = "value", num = 42 }
			local json = common.json_result(data)

			assert.is_truthy(json:find('"key"'))
			assert.is_truthy(json:find('"value"'))
		end)
	end)

	describe("list_result", function()
		it("should create result with matches and total", function()
			local items = { "a", "b", "c" }
			local result = common.list_result(items, 10)

			assert.equals(items, result.matches)
			assert.equals(3, result.total)
			assert.is_false(result.truncated)
		end)

		it("should set truncated when at max", function()
			local items = { "a", "b", "c" }
			local result = common.list_result(items, 3)

			assert.is_true(result.truncated)
		end)
	end)

	describe("with_error_handling", function()
		it("should pass through successful results", function()
			local func = function(input, opts)
				return input.value, nil
			end

			local wrapped = common.with_error_handling(func)
			local result, err = wrapped({ value = "test" }, {})

			assert.equals("test", result)
			assert.is_nil(err)
		end)

		it("should catch errors and return error message", function()
			local func = function()
				error("test error")
			end

			local wrapped = common.with_error_handling(func)
			local result, err = wrapped({}, {})

			assert.is_nil(result)
			assert.is_truthy(err:find("Internal error"))
		end)
	end)

	describe("with_validation", function()
		it("should validate before calling function", function()
			local func_called = false
			local func = function()
				func_called = true
				return "result", nil
			end

			local wrapped = common.with_validation({ "path" }, func)
			local result, err = wrapped({ path = "/test" }, {})

			assert.is_true(func_called)
			assert.equals("result", result)
		end)

		it("should return error without calling function", function()
			local func_called = false
			local func = function()
				func_called = true
				return "result", nil
			end

			local wrapped = common.with_validation({ "path" }, func)
			local result, err = wrapped({}, {})

			assert.is_false(func_called)
			assert.is_nil(result)
			assert.equals("path is required", err)
		end)
	end)
end)
