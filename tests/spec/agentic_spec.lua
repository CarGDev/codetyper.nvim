---@diagnostic disable: undefined-global
-- Unit tests for the agentic system

describe("agentic module", function()
	local agentic

	before_each(function()
		-- Reset and reload
		package.loaded["codetyper.agent.agentic"] = nil
		agentic = require("codetyper.agent.agentic")
	end)

	it("should list built-in agents", function()
		local agents = agentic.list_agents()
		assert.is_table(agents)
		assert.is_true(#agents >= 3) -- coder, planner, explorer

		local names = {}
		for _, agent in ipairs(agents) do
			names[agent.name] = true
		end

		assert.is_true(names["coder"])
		assert.is_true(names["planner"])
		assert.is_true(names["explorer"])
	end)

	it("should have description for each agent", function()
		local agents = agentic.list_agents()
		for _, agent in ipairs(agents) do
			assert.is_string(agent.description)
			assert.is_true(#agent.description > 0)
		end
	end)

	it("should mark built-in agents as builtin", function()
		local agents = agentic.list_agents()
		local coder = nil
		for _, agent in ipairs(agents) do
			if agent.name == "coder" then
				coder = agent
				break
			end
		end
		assert.is_not_nil(coder)
		assert.is_true(coder.builtin)
	end)

	it("should have init function to create directories", function()
		assert.is_function(agentic.init)
		assert.is_function(agentic.init_agents_dir)
		assert.is_function(agentic.init_rules_dir)
	end)

	it("should have run function for executing tasks", function()
		assert.is_function(agentic.run)
	end)
end)

describe("tools format conversion", function()
	local tools_module

	before_each(function()
		package.loaded["codetyper.agent.tools"] = nil
		tools_module = require("codetyper.agent.tools")
		-- Load tools
		if tools_module.load_builtins then
			pcall(tools_module.load_builtins)
		end
	end)

	it("should have to_openai_format function", function()
		assert.is_function(tools_module.to_openai_format)
	end)

	it("should have to_claude_format function", function()
		assert.is_function(tools_module.to_claude_format)
	end)

	it("should convert tools to OpenAI format", function()
		local openai_tools = tools_module.to_openai_format()
		assert.is_table(openai_tools)

		-- If tools are loaded, check format
		if #openai_tools > 0 then
			local first_tool = openai_tools[1]
			assert.equals("function", first_tool.type)
			assert.is_table(first_tool["function"])
			assert.is_string(first_tool["function"].name)
		end
	end)

	it("should convert tools to Claude format", function()
		local claude_tools = tools_module.to_claude_format()
		assert.is_table(claude_tools)

		-- If tools are loaded, check format
		if #claude_tools > 0 then
			local first_tool = claude_tools[1]
			assert.is_string(first_tool.name)
			assert.is_table(first_tool.input_schema)
		end
	end)
end)

describe("edit tool", function()
	local edit_tool

	before_each(function()
		package.loaded["codetyper.agent.tools.edit"] = nil
		edit_tool = require("codetyper.agent.tools.edit")
	end)

	it("should have name 'edit'", function()
		assert.equals("edit", edit_tool.name)
	end)

	it("should have description mentioning matching strategies", function()
		local desc = edit_tool:get_description()
		assert.is_string(desc)
		-- Should mention the matching capabilities
		assert.is_true(desc:lower():match("match") ~= nil or desc:lower():match("replac") ~= nil)
	end)

	it("should have params defined", function()
		assert.is_table(edit_tool.params)
		assert.is_true(#edit_tool.params >= 3) -- path, old_string, new_string
	end)

	it("should require path parameter", function()
		local valid, err = edit_tool:validate_input({
			old_string = "test",
			new_string = "test2",
		})
		assert.is_false(valid)
		assert.is_string(err)
	end)

	it("should require old_string parameter", function()
		local valid, err = edit_tool:validate_input({
			path = "/test",
			new_string = "test",
		})
		assert.is_false(valid)
	end)

	it("should require new_string parameter", function()
		local valid, err = edit_tool:validate_input({
			path = "/test",
			old_string = "test",
		})
		assert.is_false(valid)
	end)

	it("should accept empty old_string for new file creation", function()
		local valid, err = edit_tool:validate_input({
			path = "/test/new_file.lua",
			old_string = "",
			new_string = "new content",
		})
		assert.is_true(valid)
		assert.is_nil(err)
	end)

	it("should have func implementation", function()
		assert.is_function(edit_tool.func)
	end)
end)

describe("view tool", function()
	local view_tool

	before_each(function()
		package.loaded["codetyper.agent.tools.view"] = nil
		view_tool = require("codetyper.agent.tools.view")
	end)

	it("should have name 'view'", function()
		assert.equals("view", view_tool.name)
	end)

	it("should require path parameter", function()
		local valid, err = view_tool:validate_input({})
		assert.is_false(valid)
	end)

	it("should accept valid path", function()
		local valid, err = view_tool:validate_input({
			path = "/test/file.lua",
		})
		assert.is_true(valid)
	end)
end)

describe("write tool", function()
	local write_tool

	before_each(function()
		package.loaded["codetyper.agent.tools.write"] = nil
		write_tool = require("codetyper.agent.tools.write")
	end)

	it("should have name 'write'", function()
		assert.equals("write", write_tool.name)
	end)

	it("should require path and content parameters", function()
		local valid, err = write_tool:validate_input({})
		assert.is_false(valid)

		valid, err = write_tool:validate_input({ path = "/test" })
		assert.is_false(valid)
	end)

	it("should accept valid input", function()
		local valid, err = write_tool:validate_input({
			path = "/test/file.lua",
			content = "test content",
		})
		assert.is_true(valid)
	end)
end)

describe("grep tool", function()
	local grep_tool

	before_each(function()
		package.loaded["codetyper.agent.tools.grep"] = nil
		grep_tool = require("codetyper.agent.tools.grep")
	end)

	it("should have name 'grep'", function()
		assert.equals("grep", grep_tool.name)
	end)

	it("should require pattern parameter", function()
		local valid, err = grep_tool:validate_input({})
		assert.is_false(valid)
	end)

	it("should accept valid pattern", function()
		local valid, err = grep_tool:validate_input({
			pattern = "function.*test",
		})
		assert.is_true(valid)
	end)
end)

describe("glob tool", function()
	local glob_tool

	before_each(function()
		package.loaded["codetyper.agent.tools.glob"] = nil
		glob_tool = require("codetyper.agent.tools.glob")
	end)

	it("should have name 'glob'", function()
		assert.equals("glob", glob_tool.name)
	end)

	it("should require pattern parameter", function()
		local valid, err = glob_tool:validate_input({})
		assert.is_false(valid)
	end)

	it("should accept valid pattern", function()
		local valid, err = glob_tool:validate_input({
			pattern = "**/*.lua",
		})
		assert.is_true(valid)
	end)
end)

describe("base tool", function()
	local Base

	before_each(function()
		package.loaded["codetyper.agent.tools.base"] = nil
		Base = require("codetyper.agent.tools.base")
	end)

	it("should have validate_input method", function()
		assert.is_function(Base.validate_input)
	end)

	it("should have to_schema method", function()
		assert.is_function(Base.to_schema)
	end)

	it("should have get_description method", function()
		assert.is_function(Base.get_description)
	end)

	it("should generate valid schema", function()
		local test_tool = setmetatable({
			name = "test",
			description = "A test tool",
			params = {
				{ name = "arg1", type = "string", description = "First arg" },
				{ name = "arg2", type = "number", description = "Second arg", optional = true },
			},
		}, Base)

		local schema = test_tool:to_schema()
		assert.equals("function", schema.type)
		assert.equals("test", schema.function_def.name)
		assert.is_table(schema.function_def.parameters.properties)
		assert.is_table(schema.function_def.parameters.required)
		assert.is_true(vim.tbl_contains(schema.function_def.parameters.required, "arg1"))
		assert.is_false(vim.tbl_contains(schema.function_def.parameters.required, "arg2"))
	end)
end)
