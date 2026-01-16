---@mod codetyper.agent.loop Agent loop with tool orchestration
---@brief [[
--- Main agent loop that handles multi-turn conversations with tool use.
--- Agent execution loop with tool calling support.
---@brief ]]

local M = {}

local prompts = require("codetyper.prompts.agent.loop")

---@class AgentMessage
---@field role "system"|"user"|"assistant"|"tool"
---@field content string|table
---@field tool_call_id? string For tool responses
---@field tool_calls? table[] For assistant tool calls
---@field name? string Tool name for tool responses

---@class AgentLoopOpts
---@field system_prompt string System prompt
---@field user_input string Initial user message
---@field tools? CoderTool[] Available tools (default: all registered)
---@field max_iterations? number Max tool call iterations (default: 10)
---@field provider? string LLM provider to use
---@field on_start? fun() Called when loop starts
---@field on_chunk? fun(chunk: string) Called for each response chunk
---@field on_tool_call? fun(name: string, input: table) Called before tool execution
---@field on_tool_result? fun(name: string, result: any, error: string|nil) Called after tool execution
---@field on_message? fun(message: AgentMessage) Called for each message added
---@field on_complete? fun(result: string|nil, error: string|nil) Called when loop completes
---@field session_ctx? table Session context shared across tools

--- Format tool definitions for OpenAI-compatible API
---@param tools CoderTool[]
---@return table[]
local function format_tools_for_api(tools)
	local formatted = {}
	for _, tool in ipairs(tools) do
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

		table.insert(formatted, {
			type = "function",
			["function"] = {
				name = tool.name,
				description = type(tool.description) == "function" and tool.description() or tool.description,
				parameters = {
					type = "object",
					properties = properties,
					required = required,
				},
			},
		})
	end
	return formatted
end

--- Parse tool calls from LLM response
---@param response table LLM response
---@return table[] tool_calls
local function parse_tool_calls(response)
	local tool_calls = {}

	-- Handle different response formats
	if response.tool_calls then
		-- OpenAI format
		for _, call in ipairs(response.tool_calls) do
			local args = call["function"].arguments
			if type(args) == "string" then
				local ok, parsed = pcall(vim.json.decode, args)
				if ok then
					args = parsed
				end
			end
			table.insert(tool_calls, {
				id = call.id,
				name = call["function"].name,
				input = args,
			})
		end
	elseif response.content and type(response.content) == "table" then
		-- Claude format (content blocks)
		for _, block in ipairs(response.content) do
			if block.type == "tool_use" then
				table.insert(tool_calls, {
					id = block.id,
					name = block.name,
					input = block.input,
				})
			end
		end
	end

	return tool_calls
end

--- Build messages for LLM request
---@param history AgentMessage[]
---@return table[]
local function build_messages(history)
	local messages = {}

	for _, msg in ipairs(history) do
		if msg.role == "system" then
			table.insert(messages, {
				role = "system",
				content = msg.content,
			})
		elseif msg.role == "user" then
			table.insert(messages, {
				role = "user",
				content = msg.content,
			})
		elseif msg.role == "assistant" then
			local message = {
				role = "assistant",
				content = msg.content,
			}
			if msg.tool_calls then
				message.tool_calls = msg.tool_calls
			end
			table.insert(messages, message)
		elseif msg.role == "tool" then
			table.insert(messages, {
				role = "tool",
				tool_call_id = msg.tool_call_id,
				content = type(msg.content) == "string" and msg.content or vim.json.encode(msg.content),
			})
		end
	end

	return messages
end

--- Execute the agent loop
---@param opts AgentLoopOpts
function M.run(opts)
	local tools_mod = require("codetyper.core.tools")
	local llm = require("codetyper.core.llm")

	-- Get tools
	local tools = opts.tools or tools_mod.list()
	local tool_map = {}
	for _, tool in ipairs(tools) do
		tool_map[tool.name] = tool
	end

	-- Initialize conversation history
	---@type AgentMessage[]
	local history = {
		{ role = "system", content = opts.system_prompt },
		{ role = "user", content = opts.user_input },
	}

	local session_ctx = opts.session_ctx or {}
	local max_iterations = opts.max_iterations or 10
	local iteration = 0

	-- Callback wrappers
	local function on_message(msg)
		if opts.on_message then
			opts.on_message(msg)
		end
	end

	-- Notify of initial messages
	for _, msg in ipairs(history) do
		on_message(msg)
	end

	-- Start notification
	if opts.on_start then
		opts.on_start()
	end

	--- Process one iteration of the loop
	local function process_iteration()
		iteration = iteration + 1

		if iteration > max_iterations then
			if opts.on_complete then
				opts.on_complete(nil, "Max iterations reached")
			end
			return
		end

		-- Build request
		local messages = build_messages(history)
		local formatted_tools = format_tools_for_api(tools)

		-- Build context for LLM
		local context = {
			file_content = "",
			language = "lua",
			extension = "lua",
			prompt_type = "agent",
			tools = formatted_tools,
		}

		-- Get LLM response
		local client = llm.get_client()
		if not client then
			if opts.on_complete then
				opts.on_complete(nil, "No LLM client available")
			end
			return
		end

		-- Build prompt from messages
		local prompt_parts = {}
		for _, msg in ipairs(messages) do
			if msg.role ~= "system" then
				table.insert(prompt_parts, string.format("[%s]: %s", msg.role, msg.content or ""))
			end
		end
		local prompt = table.concat(prompt_parts, "\n\n")

		client.generate(prompt, context, function(response, error)
			if error then
				if opts.on_complete then
					opts.on_complete(nil, error)
				end
				return
			end

			-- Chunk callback
			if opts.on_chunk then
				opts.on_chunk(response)
			end

			-- Parse response for tool calls
			-- For now, we'll use a simple heuristic to detect tool calls in the response
			-- In a full implementation, the LLM would return structured tool calls
			local tool_calls = {}

			-- Try to parse JSON tool calls from response
			local json_match = response:match("```json%s*(%b{})%s*```")
			if json_match then
				local ok, parsed = pcall(vim.json.decode, json_match)
				if ok and parsed.tool_calls then
					tool_calls = parsed.tool_calls
				end
			end

			-- Add assistant message
			local assistant_msg = {
				role = "assistant",
				content = response,
				tool_calls = #tool_calls > 0 and tool_calls or nil,
			}
			table.insert(history, assistant_msg)
			on_message(assistant_msg)

			-- Process tool calls
			if #tool_calls > 0 then
				local pending = #tool_calls
				local results = {}

				for i, call in ipairs(tool_calls) do
					local tool = tool_map[call.name]
					if not tool then
						results[i] = { error = "Unknown tool: " .. call.name }
						pending = pending - 1
					else
						-- Notify of tool call
						if opts.on_tool_call then
							opts.on_tool_call(call.name, call.input)
						end

						-- Execute tool
						local tool_opts = {
							on_log = function(msg)
								pcall(function()
									local logs = require("codetyper.adapters.nvim.ui.logs")
									logs.add({ type = "tool", message = msg })
								end)
							end,
							on_complete = function(result, err)
								results[i] = { result = result, error = err }
								pending = pending - 1

								-- Notify of tool result
								if opts.on_tool_result then
									opts.on_tool_result(call.name, result, err)
								end

								-- Add tool response to history
								local tool_msg = {
									role = "tool",
									tool_call_id = call.id or tostring(i),
									name = call.name,
									content = err or result,
								}
								table.insert(history, tool_msg)
								on_message(tool_msg)

								-- Continue loop when all tools complete
								if pending == 0 then
									vim.schedule(process_iteration)
								end
							end,
							session_ctx = session_ctx,
						}

						-- Validate and execute
						local valid, validation_err = true, nil
						if tool.validate_input then
							valid, validation_err = tool:validate_input(call.input)
						end

						if not valid then
							tool_opts.on_complete(nil, validation_err)
						else
							local result, err = tool.func(call.input, tool_opts)
							-- If sync result, call on_complete
							if result ~= nil or err ~= nil then
								tool_opts.on_complete(result, err)
							end
						end
					end
				end
			else
				-- No tool calls - loop complete
				if opts.on_complete then
					opts.on_complete(response, nil)
				end
			end
		end)
	end

	-- Start the loop
	process_iteration()
end

--- Create an agent with default settings
---@param task string Task description
---@param opts? AgentLoopOpts Additional options
function M.create(task, opts)
	opts = opts or {}

	local system_prompt = opts.system_prompt or prompts.default_system_prompt

	M.run(vim.tbl_extend("force", opts, {
		system_prompt = system_prompt,
		user_input = task,
	}))
end

--- Simple dispatch agent for sub-tasks
---@param prompt string Task for the sub-agent
---@param on_complete fun(result: string|nil, error: string|nil) Completion callback
---@param opts? table Additional options
function M.dispatch(prompt, on_complete, opts)
	opts = opts or {}

	-- Sub-agents get limited tools by default
	local tools_mod = require("codetyper.core.tools")
	local safe_tools = tools_mod.list(function(tool)
		return tool.name == "view" or tool.name == "grep" or tool.name == "glob"
	end)

	M.run({
		system_prompt = prompts.dispatch_prompt,
		user_input = prompt,
		tools = opts.tools or safe_tools,
		max_iterations = opts.max_iterations or 5,
		on_complete = on_complete,
		session_ctx = opts.session_ctx,
	})
end

return M
