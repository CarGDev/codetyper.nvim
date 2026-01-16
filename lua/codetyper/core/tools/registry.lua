---@mod codetyper.agent.tools Tool registry and orchestration
---@brief [[
--- Registry for LLM tools with execution and schema generation.
--- Tool system for agent mode.
---@brief ]]

local M = {}

--- Registered tools
---@type table<string, CoderTool>
local tools = {}

--- Tool execution history for current session
---@type table[]
local execution_history = {}

--- Register a tool
---@param tool CoderTool Tool to register
function M.register(tool)
	if not tool.name then
		error("Tool must have a name")
	end
	tools[tool.name] = tool
end

--- Unregister a tool
---@param name string Tool name
function M.unregister(name)
	tools[name] = nil
end

--- Get a tool by name
---@param name string Tool name
---@return CoderTool|nil
function M.get(name)
	return tools[name]
end

--- Get all registered tools
---@return table<string, CoderTool>
function M.get_all()
	return tools
end

--- Get tools as a list
---@param filter? fun(tool: CoderTool): boolean Optional filter function
---@return CoderTool[]
function M.list(filter)
	local result = {}
	for _, tool in pairs(tools) do
		if not filter or filter(tool) then
			table.insert(result, tool)
		end
	end
	return result
end

--- Generate schemas for all tools (for LLM function calling)
---@param filter? fun(tool: CoderTool): boolean Optional filter function
---@return table[] schemas
function M.get_schemas(filter)
	local schemas = {}
	for _, tool in pairs(tools) do
		if not filter or filter(tool) then
			if tool.to_schema then
				table.insert(schemas, tool:to_schema())
			end
		end
	end
	return schemas
end

--- Execute a tool by name
---@param name string Tool name
---@param input table Input parameters
---@param opts CoderToolOpts Execution options
---@return any result
---@return string|nil error
function M.execute(name, input, opts)
	local tool = tools[name]
	if not tool then
		return nil, "Unknown tool: " .. name
	end

	-- Validate input
	if tool.validate_input then
		local valid, err = tool:validate_input(input)
		if not valid then
			return nil, err
		end
	end

	-- Log execution
	if opts.on_log then
		opts.on_log(string.format("Executing tool: %s", name))
	end

	-- Track execution
	local execution = {
		tool = name,
		input = input,
		start_time = os.time(),
		status = "running",
	}
	table.insert(execution_history, execution)

	-- Execute the tool
	local result, err = tool.func(input, opts)

	-- Update execution record
	execution.end_time = os.time()
	execution.status = err and "error" or "completed"
	execution.result = result
	execution.error = err

	return result, err
end

--- Process a tool call from LLM response
---@param tool_call table Tool call from LLM (name + input)
---@param opts CoderToolOpts Execution options
---@return any result
---@return string|nil error
function M.process_tool_call(tool_call, opts)
	local name = tool_call.name or tool_call.function_name
	local input = tool_call.input or tool_call.arguments or {}

	-- Parse JSON arguments if string
	if type(input) == "string" then
		local ok, parsed = pcall(vim.json.decode, input)
		if ok then
			input = parsed
		else
			return nil, "Failed to parse tool arguments: " .. input
		end
	end

	return M.execute(name, input, opts)
end

--- Get execution history
---@param limit? number Max entries to return
---@return table[]
function M.get_history(limit)
	if not limit then
		return execution_history
	end

	local result = {}
	local start = math.max(1, #execution_history - limit + 1)
	for i = start, #execution_history do
		table.insert(result, execution_history[i])
	end
	return result
end

--- Clear execution history
function M.clear_history()
	execution_history = {}
end

--- Load built-in tools
function M.load_builtins()
	-- View file tool
	local view = require("codetyper.core.tools.view")
	M.register(view)

	-- Bash tool
	local bash = require("codetyper.core.tools.bash")
	M.register(bash)

	-- Grep tool
	local grep = require("codetyper.core.tools.grep")
	M.register(grep)

	-- Glob tool
	local glob = require("codetyper.core.tools.glob")
	M.register(glob)

	-- Write file tool
	local write = require("codetyper.core.tools.write")
	M.register(write)

	-- Edit tool
	local edit = require("codetyper.core.tools.edit")
	M.register(edit)
end

--- Initialize tools system
function M.setup()
	M.load_builtins()
end

--- Get tool definitions for LLM (lazy-loaded, OpenAI format)
--- This is accessed as M.definitions property
M.definitions = setmetatable({}, {
	__call = function()
		-- Ensure tools are loaded
		if vim.tbl_count(tools) == 0 then
			M.load_builtins()
		end
		return M.to_openai_format()
	end,
	__index = function(_, key)
		-- Make it work as both function and table
		if key == "get" then
			return function()
				if vim.tbl_count(tools) == 0 then
					M.load_builtins()
				end
				return M.to_openai_format()
			end
		end
		return nil
	end,
})

--- Get definitions as a function (for backwards compatibility)
function M.get_definitions()
	if vim.tbl_count(tools) == 0 then
		M.load_builtins()
	end
	return M.to_openai_format()
end

--- Convert all tools to OpenAI function calling format
---@param filter? fun(tool: CoderTool): boolean Optional filter function
---@return table[] OpenAI-compatible tool definitions
function M.to_openai_format(filter)
	local openai_tools = {}

	for _, tool in pairs(tools) do
		if not filter or filter(tool) then
			local properties = {}
			local required = {}

			for _, param in ipairs(tool.params or {}) do
				properties[param.name] = {
					type = param.type == "integer" and "number" or param.type,
					description = param.description,
				}
				if param.default ~= nil then
					properties[param.name].default = param.default
				end
				if not param.optional then
					table.insert(required, param.name)
				end
			end

			local description = type(tool.description) == "function" and tool.description() or tool.description

			table.insert(openai_tools, {
				type = "function",
				["function"] = {
					name = tool.name,
					description = description,
					parameters = {
						type = "object",
						properties = properties,
						required = required,
					},
				},
			})
		end
	end

	return openai_tools
end

--- Convert all tools to Claude tool use format
---@param filter? fun(tool: CoderTool): boolean Optional filter function
---@return table[] Claude-compatible tool definitions
function M.to_claude_format(filter)
	local claude_tools = {}

	for _, tool in pairs(tools) do
		if not filter or filter(tool) then
			local properties = {}
			local required = {}

			for _, param in ipairs(tool.params or {}) do
				properties[param.name] = {
					type = param.type == "integer" and "number" or param.type,
					description = param.description,
				}
				if not param.optional then
					table.insert(required, param.name)
				end
			end

			local description = type(tool.description) == "function" and tool.description() or tool.description

			table.insert(claude_tools, {
				name = tool.name,
				description = description,
				input_schema = {
					type = "object",
					properties = properties,
					required = required,
				},
			})
		end
	end

	return claude_tools
end

return M
