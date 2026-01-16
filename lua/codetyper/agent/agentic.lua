---@mod codetyper.agent.agentic Agentic loop with proper tool calling
---@brief [[
--- Full agentic system that handles multi-file changes via tool calling.
--- Multi-file agent system with tool orchestration.
---@brief ]]

local M = {}

---@class AgenticMessage
---@field role "system"|"user"|"assistant"|"tool"
---@field content string|table
---@field tool_calls? table[] For assistant messages with tool calls
---@field tool_call_id? string For tool result messages
---@field name? string Tool name for tool results

---@class AgenticToolCall
---@field id string Unique tool call ID
---@field type "function"
---@field function {name: string, arguments: string|table}

---@class AgenticOpts
---@field task string The task to accomplish
---@field files? string[] Initial files to include as context
---@field agent? string Agent name to use (default: "coder")
---@field model? string Model override
---@field max_iterations? number Max tool call rounds (default: 20)
---@field on_message? fun(msg: AgenticMessage) Called for each message
---@field on_tool_start? fun(name: string, args: table) Called before tool execution
---@field on_tool_end? fun(name: string, result: any, error: string|nil) Called after tool execution
---@field on_file_change? fun(path: string, action: string) Called when file is modified
---@field on_complete? fun(result: string|nil, error: string|nil) Called when done
---@field on_status? fun(status: string) Status updates

local utils = require("codetyper.utils")

--- Load agent definition
---@param name string Agent name
---@return table|nil agent definition
local function load_agent(name)
	local agents_dir = vim.fn.getcwd() .. "/.coder/agents"
	local agent_file = agents_dir .. "/" .. name .. ".md"

	-- Check if custom agent exists
	if vim.fn.filereadable(agent_file) == 1 then
		local content = table.concat(vim.fn.readfile(agent_file), "\n")
		-- Parse frontmatter and content
		local frontmatter = {}
		local body = content

		local fm_match = content:match("^%-%-%-\n(.-)%-%-%-\n(.*)$")
		if fm_match then
			-- Parse YAML-like frontmatter
			for line in content:match("^%-%-%-\n(.-)%-%-%-"):gmatch("[^\n]+") do
				local key, value = line:match("^(%w+):%s*(.+)$")
				if key and value then
					frontmatter[key] = value
				end
			end
			body = content:match("%-%-%-\n.-%-%-%-%s*\n(.*)$") or content
		end

		return {
			name = name,
			description = frontmatter.description or "Custom agent: " .. name,
			system_prompt = body,
			tools = frontmatter.tools and vim.split(frontmatter.tools, ",") or nil,
			model = frontmatter.model,
		}
	end

	-- Built-in agents
	local builtin_agents = require("codetyper.prompts.agents.personas").builtin

	return builtin_agents[name]
end

--- Load rules from .coder/rules/
---@return string Combined rules content
local function load_rules()
	local rules_dir = vim.fn.getcwd() .. "/.coder/rules"
	local rules = {}

	if vim.fn.isdirectory(rules_dir) == 1 then
		local files = vim.fn.glob(rules_dir .. "/*.md", false, true)
		for _, file in ipairs(files) do
			local content = table.concat(vim.fn.readfile(file), "\n")
			local filename = vim.fn.fnamemodify(file, ":t:r")
			table.insert(rules, string.format("## Rule: %s\n%s", filename, content))
		end
	end

	if #rules > 0 then
		return "\n\n# Project Rules\n" .. table.concat(rules, "\n\n")
	end
	return ""
end

--- Build messages array for API request
---@param history AgenticMessage[]
---@param provider string "openai"|"claude"
---@return table[] Formatted messages
local function build_messages(history, provider)
	local messages = {}

	for _, msg in ipairs(history) do
		if msg.role == "system" then
			if provider == "claude" then
				-- Claude uses system parameter, not message
				-- Skip system messages in array
			else
				table.insert(messages, {
					role = "system",
					content = msg.content,
				})
			end
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
				if provider == "claude" then
					-- Claude format: content is array of blocks
					message.content = {}
					if msg.content and msg.content ~= "" then
						table.insert(message.content, {
							type = "text",
							text = msg.content,
						})
					end
					for _, tc in ipairs(msg.tool_calls) do
						table.insert(message.content, {
							type = "tool_use",
							id = tc.id,
							name = tc["function"].name,
							input = type(tc["function"].arguments) == "string"
									and vim.json.decode(tc["function"].arguments)
								or tc["function"].arguments,
						})
					end
				end
			end
			table.insert(messages, message)
		elseif msg.role == "tool" then
			if provider == "claude" then
				table.insert(messages, {
					role = "user",
					content = {
						{
							type = "tool_result",
							tool_use_id = msg.tool_call_id,
							content = msg.content,
						},
					},
				})
			else
				table.insert(messages, {
					role = "tool",
					tool_call_id = msg.tool_call_id,
					content = type(msg.content) == "string" and msg.content or vim.json.encode(msg.content),
				})
			end
		end
	end

	return messages
end

--- Build tools array for API request
---@param tool_names string[] Tool names to include
---@param provider string "openai"|"claude"
---@return table[] Formatted tools
local function build_tools(tool_names, provider)
	local tools_mod = require("codetyper.agent.tools")
	local tools = {}

	for _, name in ipairs(tool_names) do
		local tool = tools_mod.get(name)
		if tool then
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

			if provider == "claude" then
				table.insert(tools, {
					name = tool.name,
					description = description,
					input_schema = {
						type = "object",
						properties = properties,
						required = required,
					},
				})
			else
				table.insert(tools, {
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
	end

	return tools
end

--- Execute a tool call
---@param tool_call AgenticToolCall
---@param opts AgenticOpts
---@return string result
---@return string|nil error
local function execute_tool(tool_call, opts)
	local tools_mod = require("codetyper.agent.tools")
	local name = tool_call["function"].name
	local args = tool_call["function"].arguments

	-- Parse arguments if string
	if type(args) == "string" then
		local ok, parsed = pcall(vim.json.decode, args)
		if ok then
			args = parsed
		else
			return "", "Failed to parse tool arguments: " .. args
		end
	end

	-- Notify tool start
	if opts.on_tool_start then
		opts.on_tool_start(name, args)
	end

	if opts.on_status then
		opts.on_status("Executing: " .. name)
	end

	-- Execute the tool
	local tool = tools_mod.get(name)
	if not tool then
		local err = "Unknown tool: " .. name
		if opts.on_tool_end then
			opts.on_tool_end(name, nil, err)
		end
		return "", err
	end

	local result, err = tool.func(args, {
		on_log = function(msg)
			if opts.on_status then
				opts.on_status(msg)
			end
		end,
	})

	-- Notify tool end
	if opts.on_tool_end then
		opts.on_tool_end(name, result, err)
	end

	-- Track file changes
	if opts.on_file_change and (name == "write" or name == "edit") and not err then
		opts.on_file_change(args.path, name == "write" and "created" or "modified")
	end

	if err then
		return "", err
	end

	return type(result) == "string" and result or vim.json.encode(result), nil
end

--- Parse tool calls from LLM response (unified Claude-like format)
---@param response table Raw API response in unified format
---@param provider string Provider name (unused, kept for signature compatibility)
---@return AgenticToolCall[]
local function parse_tool_calls(response, provider)
	local tool_calls = {}

	-- Unified format: content array with tool_use blocks
	local content = response.content or {}
	for _, block in ipairs(content) do
		if block.type == "tool_use" then
			-- OpenAI expects arguments as JSON string, not table
			local args = block.input
			if type(args) == "table" then
				args = vim.json.encode(args)
			end

			table.insert(tool_calls, {
				id = block.id or utils.generate_id("call"),
				type = "function",
				["function"] = {
					name = block.name,
					arguments = args,
				},
			})
		end
	end

	return tool_calls
end

--- Extract text content from response (unified Claude-like format)
---@param response table Raw API response in unified format
---@param provider string Provider name (unused, kept for signature compatibility)
---@return string
local function extract_content(response, provider)
	local parts = {}
	for _, block in ipairs(response.content or {}) do
		if block.type == "text" then
			table.insert(parts, block.text)
		end
	end
	return table.concat(parts, "\n")
end

--- Check if response indicates completion (unified Claude-like format)
---@param response table Raw API response in unified format
---@param provider string Provider name (unused, kept for signature compatibility)
---@return boolean
local function is_complete(response, provider)
	return response.stop_reason == "end_turn"
end

--- Make API request to LLM with native tool calling support
---@param messages table[] Formatted messages
---@param tools table[] Formatted tools
---@param system_prompt string System prompt
---@param provider string "openai"|"claude"|"copilot"
---@param model string Model name
---@param callback fun(response: table|nil, error: string|nil)
local function call_llm(messages, tools, system_prompt, provider, model, callback)
	local context = {
		language = "lua",
		file_content = "",
		prompt_type = "agent",
		project_root = vim.fn.getcwd(),
		cwd = vim.fn.getcwd(),
	}

	-- Use native tool calling APIs
	if provider == "copilot" then
		local client = require("codetyper.llm.copilot")

		-- Copilot's generate_with_tools expects messages in a specific format
		-- Convert to the format it expects
		local converted_messages = {}
		for _, msg in ipairs(messages) do
			if msg.role ~= "system" then
				table.insert(converted_messages, msg)
			end
		end

		client.generate_with_tools(converted_messages, context, tools, function(response, err)
			if err then
				callback(nil, err)
				return
			end

			-- Response is already in Claude-like format from the provider
			-- Convert to our internal format
			local result = {
				content = {},
				stop_reason = "end_turn",
			}

			if response and response.content then
				for _, block in ipairs(response.content) do
					if block.type == "text" then
						table.insert(result.content, { type = "text", text = block.text })
					elseif block.type == "tool_use" then
						table.insert(result.content, {
							type = "tool_use",
							id = block.id or utils.generate_id("call"),
							name = block.name,
							input = block.input,
						})
						result.stop_reason = "tool_use"
					end
				end
			end

			callback(result, nil)
		end)
	elseif provider == "openai" then
		local client = require("codetyper.llm.openai")

		-- OpenAI's generate_with_tools
		local converted_messages = {}
		for _, msg in ipairs(messages) do
			if msg.role ~= "system" then
				table.insert(converted_messages, msg)
			end
		end

		client.generate_with_tools(converted_messages, context, tools, function(response, err)
			if err then
				callback(nil, err)
				return
			end

			-- Response is already in Claude-like format from the provider
			local result = {
				content = {},
				stop_reason = "end_turn",
			}

			if response and response.content then
				for _, block in ipairs(response.content) do
					if block.type == "text" then
						table.insert(result.content, { type = "text", text = block.text })
					elseif block.type == "tool_use" then
						table.insert(result.content, {
							type = "tool_use",
							id = block.id or utils.generate_id("call"),
							name = block.name,
							input = block.input,
						})
						result.stop_reason = "tool_use"
					end
				end
			end

			callback(result, nil)
		end)
	elseif provider == "ollama" then
		local client = require("codetyper.llm.ollama")

		-- Ollama's generate_with_tools (text-based tool calling)
		local converted_messages = {}
		for _, msg in ipairs(messages) do
			if msg.role ~= "system" then
				table.insert(converted_messages, msg)
			end
		end

		client.generate_with_tools(converted_messages, context, tools, function(response, err)
			if err then
				callback(nil, err)
				return
			end

			-- Response is already in Claude-like format from the provider
			callback(response, nil)
		end)
	else
		-- Fallback for other providers (ollama, etc.) - use text-based parsing
		local client = require("codetyper.llm." .. provider)

		-- Build prompt from messages
		local prompts = require("codetyper.prompts.agent")
		local prompt_parts = {}
		for _, msg in ipairs(messages) do
			if msg.role == "user" then
				local content = type(msg.content) == "string" and msg.content or vim.json.encode(msg.content)
				table.insert(prompt_parts, prompts.text_user_prefix .. content)
			elseif msg.role == "assistant" then
				local content = type(msg.content) == "string" and msg.content or vim.json.encode(msg.content)
				table.insert(prompt_parts, prompts.text_assistant_prefix .. content)
			end
		end

		-- Add tool descriptions to prompt for text-based providers
		local tool_desc = require("codetyper.prompts.agent").tool_instructions_text
		for _, tool in ipairs(tools) do
			local name = tool.name or (tool["function"] and tool["function"].name)
			local desc = tool.description or (tool["function"] and tool["function"].description)
			if name then
				tool_desc = tool_desc .. string.format("- **%s**: %s\n", name, desc or "")
			end
		end

		context.file_content = system_prompt .. tool_desc

		client.generate(table.concat(prompt_parts, "\n\n"), context, function(response, err)
			if err then
				callback(nil, err)
				return
			end

			-- Parse response for tool calls (text-based fallback)
			local result = {
				content = {},
				stop_reason = "end_turn",
			}

			-- Extract text content
			local text_content = response

			-- Try to extract JSON tool calls from response
			local json_match = response:match("```json%s*(%b{})%s*```")
			if json_match then
				local ok, parsed = pcall(vim.json.decode, json_match)
				if ok and parsed.tool then
					table.insert(result.content, {
						type = "tool_use",
						id = utils.generate_id("call"),
						name = parsed.tool,
						input = parsed.arguments or {},
					})
					text_content = response:gsub("```json.-```", ""):gsub("^%s+", ""):gsub("%s+$", "")
					result.stop_reason = "tool_use"
				end
			end

			if text_content and text_content ~= "" then
				table.insert(result.content, 1, { type = "text", text = text_content })
			end

			callback(result, nil)
		end)
	end
end

--- Run the agentic loop
---@param opts AgenticOpts
function M.run(opts)
	-- Load agent
	local agent = load_agent(opts.agent or "coder")
	if not agent then
		if opts.on_complete then
			opts.on_complete(nil, "Unknown agent: " .. (opts.agent or "coder"))
		end
		return
	end

	-- Load rules
	local rules = load_rules()

	-- Build system prompt
	local system_prompt = agent.system_prompt .. rules

	-- Initialize message history
	---@type AgenticMessage[]
	local history = {
		{ role = "system", content = system_prompt },
	}

	-- Add initial file context if provided
	if opts.files and #opts.files > 0 then
		local file_context = require("codetyper.prompts.agent").format_file_context(opts.files)
		table.insert(history, { role = "user", content = file_context })
		table.insert(history, { role = "assistant", content = "I've reviewed the provided files. What would you like me to do?" })
	end

	-- Add the task
	table.insert(history, { role = "user", content = opts.task })

	-- Determine provider
	local config = require("codetyper").get_config()
	local provider = config.llm.provider or "copilot"
	-- Note: Ollama has its own handler in call_llm, don't change it

	-- Get tools for this agent
	local tool_names = agent.tools or { "view", "edit", "write", "grep", "glob", "bash" }

	-- Ensure tools are loaded
	local tools_mod = require("codetyper.agent.tools")
	tools_mod.setup()

	-- Build tools for API
	local tools = build_tools(tool_names, provider)

	-- Iteration tracking
	local iteration = 0
	local max_iterations = opts.max_iterations or 20

	--- Process one iteration
	local function process_iteration()
		iteration = iteration + 1

		if iteration > max_iterations then
			if opts.on_complete then
				opts.on_complete(nil, "Max iterations reached")
			end
			return
		end

		if opts.on_status then
			opts.on_status(string.format("Thinking... (iteration %d)", iteration))
		end

		-- Build messages for API
		local messages = build_messages(history, provider)

		-- Call LLM
		call_llm(messages, tools, system_prompt, provider, opts.model, function(response, err)
			if err then
				if opts.on_complete then
					opts.on_complete(nil, err)
				end
				return
			end

			-- Extract content and tool calls
			local content = extract_content(response, provider)
			local tool_calls = parse_tool_calls(response, provider)

			-- Add assistant message to history
			local assistant_msg = {
				role = "assistant",
				content = content,
				tool_calls = #tool_calls > 0 and tool_calls or nil,
			}
			table.insert(history, assistant_msg)

			if opts.on_message then
				opts.on_message(assistant_msg)
			end

			-- Process tool calls if any
			if #tool_calls > 0 then
				for _, tc in ipairs(tool_calls) do
					local result, tool_err = execute_tool(tc, opts)

					-- Add tool result to history
					local tool_msg = {
						role = "tool",
						tool_call_id = tc.id,
						name = tc["function"].name,
						content = tool_err or result,
					}
					table.insert(history, tool_msg)

					if opts.on_message then
						opts.on_message(tool_msg)
					end
				end

				-- Continue the loop
				vim.schedule(process_iteration)
			else
				-- No tool calls - check if complete
				if is_complete(response, provider) or content ~= "" then
					if opts.on_complete then
						opts.on_complete(content, nil)
					end
				else
					-- Continue if not explicitly complete
					vim.schedule(process_iteration)
				end
			end
		end)
	end

	-- Start the loop
	process_iteration()
end

--- Create default agent files in .coder/agents/
function M.init_agents_dir()
	local agents_dir = vim.fn.getcwd() .. "/.coder/agents"
	vim.fn.mkdir(agents_dir, "p")

	-- Create example agent
	local example_agent = require("codetyper.prompts.agents.templates").agent

	local example_path = agents_dir .. "/example.md"
	if vim.fn.filereadable(example_path) ~= 1 then
		vim.fn.writefile(vim.split(example_agent, "\n"), example_path)
	end

	return agents_dir
end

--- Create default rules in .coder/rules/
function M.init_rules_dir()
	local rules_dir = vim.fn.getcwd() .. "/.coder/rules"
	vim.fn.mkdir(rules_dir, "p")

	-- Create example rule
	local example_rule = require("codetyper.prompts.agents.templates").rule

	local example_path = rules_dir .. "/code-style.md"
	if vim.fn.filereadable(example_path) ~= 1 then
		vim.fn.writefile(vim.split(example_rule, "\n"), example_path)
	end

	return rules_dir
end

--- Initialize both agents and rules directories
function M.init()
	M.init_agents_dir()
	M.init_rules_dir()
end

--- List available agents
---@return table[] List of {name, description, builtin}
function M.list_agents()
	local agents = {}

	-- Built-in agents
	local personas = require("codetyper.prompts.agents.personas").builtin
	local builtins = vim.tbl_keys(personas)
	table.sort(builtins)

	for _, name in ipairs(builtins) do
		local agent = load_agent(name)
		if agent then
			table.insert(agents, {
				name = agent.name,
				description = agent.description,
				builtin = true,
			})
		end
	end

	-- Custom agents from .coder/agents/
	local agents_dir = vim.fn.getcwd() .. "/.coder/agents"
	if vim.fn.isdirectory(agents_dir) == 1 then
		local files = vim.fn.glob(agents_dir .. "/*.md", false, true)
		for _, file in ipairs(files) do
			local name = vim.fn.fnamemodify(file, ":t:r")
			if not vim.tbl_contains(builtins, name) then
				local agent = load_agent(name)
				if agent then
					table.insert(agents, {
						name = agent.name,
						description = agent.description,
						builtin = false,
					})
				end
			end
		end
	end

	return agents
end

return M
