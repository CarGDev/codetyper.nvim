--- Tests for agent tools system

describe("codetyper.agent.tools", function()
	local tools

	before_each(function()
		tools = require("codetyper.agent.tools")
		-- Clear any existing registrations
		for name, _ in pairs(tools.get_all()) do
			tools.unregister(name)
		end
	end)

	describe("tool registration", function()
		it("should register a tool", function()
			local test_tool = {
				name = "test_tool",
				description = "A test tool",
				params = {
					{ name = "input", type = "string", description = "Test input" },
				},
				func = function(input, opts)
					return "result", nil
				end,
			}

			tools.register(test_tool)
			local retrieved = tools.get("test_tool")

			assert.is_not_nil(retrieved)
			assert.equals("test_tool", retrieved.name)
		end)

		it("should unregister a tool", function()
			local test_tool = {
				name = "temp_tool",
				description = "Temporary",
				func = function() end,
			}

			tools.register(test_tool)
			assert.is_not_nil(tools.get("temp_tool"))

			tools.unregister("temp_tool")
			assert.is_nil(tools.get("temp_tool"))
		end)

		it("should list all tools", function()
			tools.register({ name = "tool1", func = function() end })
			tools.register({ name = "tool2", func = function() end })
			tools.register({ name = "tool3", func = function() end })

			local list = tools.list()
			assert.equals(3, #list)
		end)

		it("should filter tools with predicate", function()
			tools.register({ name = "safe_tool", requires_confirmation = false, func = function() end })
			tools.register({ name = "dangerous_tool", requires_confirmation = true, func = function() end })

			local safe_list = tools.list(function(t)
				return not t.requires_confirmation
			end)

			assert.equals(1, #safe_list)
			assert.equals("safe_tool", safe_list[1].name)
		end)
	end)

	describe("tool execution", function()
		it("should execute a tool and return result", function()
			tools.register({
				name = "adder",
				params = {
					{ name = "a", type = "number" },
					{ name = "b", type = "number" },
				},
				func = function(input, opts)
					return input.a + input.b, nil
				end,
			})

			local result, err = tools.execute("adder", { a = 5, b = 3 }, {})

			assert.is_nil(err)
			assert.equals(8, result)
		end)

		it("should return error for unknown tool", function()
			local result, err = tools.execute("nonexistent", {}, {})

			assert.is_nil(result)
			assert.truthy(err:match("Unknown tool"))
		end)

		it("should track execution history", function()
			tools.clear_history()
			tools.register({
				name = "tracked_tool",
				func = function()
					return "done", nil
				end,
			})

			tools.execute("tracked_tool", {}, {})
			tools.execute("tracked_tool", {}, {})

			local history = tools.get_history()
			assert.equals(2, #history)
			assert.equals("tracked_tool", history[1].tool)
			assert.equals("completed", history[1].status)
		end)
	end)

	describe("tool schemas", function()
		it("should generate JSON schema for tools", function()
			tools.register({
				name = "schema_test",
				description = "Test schema generation",
				params = {
					{ name = "required_param", type = "string", description = "A required param" },
					{ name = "optional_param", type = "number", description = "Optional", optional = true },
				},
				returns = {
					{ name = "result", type = "string" },
				},
				to_schema = require("codetyper.agent.tools.base").to_schema,
				func = function() end,
			})

			local schemas = tools.get_schemas()
			assert.equals(1, #schemas)

			local schema = schemas[1]
			assert.equals("function", schema.type)
			assert.equals("schema_test", schema.function_def.name)
			assert.is_not_nil(schema.function_def.parameters.properties.required_param)
			assert.is_not_nil(schema.function_def.parameters.properties.optional_param)
		end)
	end)

	describe("process_tool_call", function()
		it("should process tool call with name and input", function()
			tools.register({
				name = "processor_test",
				func = function(input, opts)
					return "processed: " .. input.value, nil
				end,
			})

			local result, err = tools.process_tool_call({
				name = "processor_test",
				input = { value = "test" },
			}, {})

			assert.is_nil(err)
			assert.equals("processed: test", result)
		end)

		it("should parse JSON string arguments", function()
			tools.register({
				name = "json_parser_test",
				func = function(input, opts)
					return input.key, nil
				end,
			})

			local result, err = tools.process_tool_call({
				name = "json_parser_test",
				arguments = '{"key": "value"}',
			}, {})

			assert.is_nil(err)
			assert.equals("value", result)
		end)
	end)
end)

describe("codetyper.agent.tools.base", function()
	local base

	before_each(function()
		base = require("codetyper.agent.tools.base")
	end)

	describe("validate_input", function()
		it("should validate required parameters", function()
			local tool = setmetatable({
				params = {
					{ name = "required", type = "string" },
					{ name = "optional", type = "string", optional = true },
				},
			}, base)

			local valid, err = tool:validate_input({ required = "value" })
			assert.is_true(valid)
			assert.is_nil(err)
		end)

		it("should fail on missing required parameter", function()
			local tool = setmetatable({
				params = {
					{ name = "required", type = "string" },
				},
			}, base)

			local valid, err = tool:validate_input({})
			assert.is_false(valid)
			assert.truthy(err:match("Missing required parameter"))
		end)

		it("should validate parameter types", function()
			local tool = setmetatable({
				params = {
					{ name = "num", type = "number" },
				},
			}, base)

			local valid1, _ = tool:validate_input({ num = 42 })
			assert.is_true(valid1)

			local valid2, err2 = tool:validate_input({ num = "not a number" })
			assert.is_false(valid2)
			assert.truthy(err2:match("must be number"))
		end)

		it("should validate integer type", function()
			local tool = setmetatable({
				params = {
					{ name = "int", type = "integer" },
				},
			}, base)

			local valid1, _ = tool:validate_input({ int = 42 })
			assert.is_true(valid1)

			local valid2, err2 = tool:validate_input({ int = 42.5 })
			assert.is_false(valid2)
			assert.truthy(err2:match("must be an integer"))
		end)
	end)

	describe("get_description", function()
		it("should return string description", function()
			local tool = setmetatable({
				description = "Static description",
			}, base)

			assert.equals("Static description", tool:get_description())
		end)

		it("should call function description", function()
			local tool = setmetatable({
				description = function()
					return "Dynamic description"
				end,
			}, base)

			assert.equals("Dynamic description", tool:get_description())
		end)
	end)

	describe("to_schema", function()
		it("should generate valid schema", function()
			local tool = setmetatable({
				name = "test",
				description = "Test tool",
				params = {
					{ name = "input", type = "string", description = "Input value" },
					{ name = "count", type = "integer", description = "Count", optional = true },
				},
			}, base)

			local schema = tool:to_schema()

			assert.equals("function", schema.type)
			assert.equals("test", schema.function_def.name)
			assert.equals("Test tool", schema.function_def.description)
			assert.equals("object", schema.function_def.parameters.type)
			assert.is_not_nil(schema.function_def.parameters.properties.input)
			assert.is_not_nil(schema.function_def.parameters.properties.count)
			assert.same({ "input" }, schema.function_def.parameters.required)
		end)
	end)
end)

describe("built-in tools", function()
	describe("view tool", function()
		local view

		before_each(function()
			view = require("codetyper.agent.tools.view")
		end)

		it("should have required fields", function()
			assert.equals("view", view.name)
			assert.is_string(view.description)
			assert.is_table(view.params)
			assert.is_function(view.func)
		end)

		it("should require path parameter", function()
			local result, err = view.func({}, {})
			assert.is_nil(result)
			assert.truthy(err:match("path is required"))
		end)
	end)

	describe("grep tool", function()
		local grep

		before_each(function()
			grep = require("codetyper.agent.tools.grep")
		end)

		it("should have required fields", function()
			assert.equals("grep", grep.name)
			assert.is_string(grep.description)
			assert.is_table(grep.params)
			assert.is_function(grep.func)
		end)

		it("should require pattern parameter", function()
			local result, err = grep.func({}, {})
			assert.is_nil(result)
			assert.truthy(err:match("pattern is required"))
		end)
	end)

	describe("glob tool", function()
		local glob

		before_each(function()
			glob = require("codetyper.agent.tools.glob")
		end)

		it("should have required fields", function()
			assert.equals("glob", glob.name)
			assert.is_string(glob.description)
			assert.is_table(glob.params)
			assert.is_function(glob.func)
		end)

		it("should require pattern parameter", function()
			local result, err = glob.func({}, {})
			assert.is_nil(result)
			assert.truthy(err:match("pattern is required"))
		end)
	end)

	describe("edit tool", function()
		local edit

		before_each(function()
			edit = require("codetyper.agent.tools.edit")
		end)

		it("should have required fields", function()
			assert.equals("edit", edit.name)
			assert.is_string(edit.description)
			assert.is_table(edit.params)
			assert.is_function(edit.func)
		end)

		it("should require path parameter", function()
			local result, err = edit.func({}, {})
			assert.is_nil(result)
			assert.truthy(err:match("path is required"))
		end)

		it("should require old_string parameter", function()
			local result, err = edit.func({ path = "/tmp/test" }, {})
			assert.is_nil(result)
			assert.truthy(err:match("old_string is required"))
		end)
	end)

	describe("write tool", function()
		local write

		before_each(function()
			write = require("codetyper.agent.tools.write")
		end)

		it("should have required fields", function()
			assert.equals("write", write.name)
			assert.is_string(write.description)
			assert.is_table(write.params)
			assert.is_function(write.func)
		end)

		it("should require path parameter", function()
			local result, err = write.func({}, {})
			assert.is_nil(result)
			assert.truthy(err:match("path is required"))
		end)

		it("should require content parameter", function()
			local result, err = write.func({ path = "/tmp/test" }, {})
			assert.is_nil(result)
			assert.truthy(err:match("content is required"))
		end)
	end)

	describe("bash tool", function()
		local bash

		before_each(function()
			bash = require("codetyper.agent.tools.bash")
		end)

		it("should have required fields", function()
			assert.equals("bash", bash.name)
			assert.is_function(bash.func)
		end)

		it("should require command parameter", function()
			local result, err = bash.func({}, {})
			assert.is_nil(result)
			assert.truthy(err:match("command is required"))
		end)

		it("should require confirmation by default", function()
			assert.is_true(bash.requires_confirmation)
		end)
	end)
end)
