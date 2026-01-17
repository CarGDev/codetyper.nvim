---@mod codetyper.agent.agentic Agentic loop with proper tool calling
---@brief [[
--- Full agentic system that handles multi-file changes via tool calling.
--- Multi-file agent system with tool orchestration.
---@brief ]]

local M = {}

-- Middleware modules
local session = require("codetyper.features.agents.middleware.session")
local permissions = require("codetyper.features.agents.middleware.permissions")
local hooks = require("codetyper.features.agents.middleware.hooks")
local retry = require("codetyper.features.agents.middleware.retry")

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

local utils = require("codetyper.support.utils")

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
	local ok_personas, personas_mod = pcall(require, "codetyper.prompts.agents.personas")
local builtin_agents = ok_personas and personas_mod.builtin or {}

-- If personas are missing (prompts moved to agent), persona list is empty

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
	local tools_mod = require("codetyper.core.tools")
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
--- Tool name aliases to map common LLM tool names to our tool names
local TOOL_ALIASES = {
	read_file = "view",
	read = "view",
	cat = "view",
	file_read = "view",
	get_file = "view",
	write_file = "write",
	create_file = "write",
	file_write = "write",
	save_file = "write",
	edit_file = "edit",
	modify_file = "edit",
	file_edit = "edit",
	search = "grep",
	find = "glob",
	find_files = "glob",
	list_files = "glob",
	run = "bash",
	execute = "bash",
	shell = "bash",
	command = "bash",
}

---@return string result
---@return string|nil error
local function execute_tool(tool_call, opts)
	local tools_mod = require("codetyper.core.tools")
	local name = tool_call["function"].name
	local args = tool_call["function"].arguments

	-- Map tool name aliases
	if TOOL_ALIASES[name] then
		name = TOOL_ALIASES[name]
	end

	-- Parse arguments if string
	if type(args) == "string" then
		local ok, parsed = pcall(vim.json.decode, args)
		if ok then
			args = parsed
		else
			return "", "Failed to parse tool arguments: " .. args
		end
	end

	-- 1. PERMISSION CHECK
	local perm = permissions.check(name, args, {})
	if not perm.allowed and not perm.auto then
		-- Tool requires approval
		local approval_msg = string.format(
			"Tool '%s' requires approval: %s\n\nArguments: %s\n\nApprove? (y/n)",
			name,
			perm.reason,
			vim.inspect(args)
		)

		-- For now, auto-deny (in future, show UI prompt)
		-- TODO: Integrate with confirmation UI
		local err = "Permission denied: " .. perm.reason
		if opts.on_tool_end then
			opts.on_tool_end(name, nil, err)
		end
		return "", err
	end

	-- Grant permission for session if approved
	if perm.allowed and not perm.auto then
		permissions.grant(name, args, "session")
	end

	-- 2. PRE-TOOL HOOK
	local hook_ctx = hooks.start_timing({
		tool_name = name,
		input = args,
	})

	if not hooks.invoke("pre_tool", hook_ctx) then
		local err = "Pre-tool hook rejected execution"
		if opts.on_tool_end then
			opts.on_tool_end(name, nil, err)
		end
		return "", err
	end

	-- Notify tool start
	if opts.on_tool_start then
		opts.on_tool_start(name, args)
	end

	if opts.on_status then
		opts.on_status("Executing: " .. name)
	end

	-- 3. EXECUTE WITH RETRY
	local tool = tools_mod.get(name)
	if not tool then
		local err = "Unknown tool: " .. name
		hook_ctx.error = err
		hooks.end_timing(hook_ctx)
		hooks.invoke("post_tool", hook_ctx)

		if opts.on_tool_end then
			opts.on_tool_end(name, nil, err)
		end
		return "", err
	end

	local result, err

	-- Wrap tool execution with retry for network/temporary errors
	local retry_result = retry.with_retry_sync(function()
		local r, e = tool.func(args, {
			on_log = function(msg)
				if opts.on_status then
					opts.on_status(msg)
				end
			end,
		})

		if e then
			error(e)
		end

		return r
	end, retry.policies.network)

	if retry_result.success then
		result = retry_result.result
		err = nil
	else
		result = nil
		err = retry_result.error
	end

	-- 4. POST-TOOL HOOK
	hook_ctx.result = result
	hook_ctx.error = err
	hooks.end_timing(hook_ctx)
	hooks.invoke("post_tool", hook_ctx)

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
		local client = require("codetyper.core.llm.copilot")

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
		local client = require("codetyper.core.llm.openai")

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
		local client = require("codetyper.core.llm.ollama")

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
		local client = require("codetyper.core.llm." .. provider)

		-- Build prompt from messages
		local prompts = require("codetyper.prompts.agents")
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
		local tool_desc = require("codetyper.prompts.agents").tool_instructions_text
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
	-- Create new session for this agent run
	session.create({ context = { agent = opts.agent or "coder" } })

	-- Load agent
	local agent = load_agent(opts.agent or "coder")
	if not agent then
		session.clear()
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
		local file_context = require("codetyper.prompts.agents").format_file_context(opts.files)
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
	local tools_mod = require("codetyper.core.tools")
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
			session.clear()
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
				session.clear()
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
					session.clear()
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

--- Run the agentic loop with planner (multi-phase workflow)
---@param opts AgenticOpts
function M.run_with_planner(opts)
	local planner = require("codetyper.features.agents.planner")
	local brain = require("codetyper.features.agents.brain")
	local memory = require("codetyper.features.agents.memory")

	-- Load long-term knowledge
	local knowledge = brain.load()

	-- Create working memory for this task
	memory.create(opts.task)

	-- Create planner state
	local state = planner.create(opts.task, {
		on_phase_change = function(phase)
			memory.set_phase(phase)
			if opts.on_status then
				opts.on_status(string.format("Phase: %s | %s", phase, brain.get_summary(knowledge)))
			end
		end,
		on_plan_ready = opts.on_plan_ready,
		on_step_complete = opts.on_step_complete,
	})

	-- Create session
	session.create({ context = { agent = opts.agent or "coder", mode = "planner" } })

	-- Load agent
	local agent = load_agent(opts.agent or "coder")
	if not agent then
		session.clear()
		if opts.on_complete then
			opts.on_complete(nil, "Unknown agent: " .. (opts.agent or "coder"))
		end
		return
	end

	-- Load rules
	local rules = load_rules()

	-- Determine provider
	local config = require("codetyper").get_config()
	local provider = config.llm.provider or "copilot"

	-- Ensure tools are loaded
	local tools_mod = require("codetyper.core.tools")
	tools_mod.setup()

	---@type AgenticMessage[]
	local history = {}
	local iteration = 0
	local max_iterations = opts.max_iterations or 30

	--- Process one iteration based on current phase
	local function process_iteration()
		iteration = iteration + 1

		if iteration > max_iterations then
			session.clear()
			memory.clear()
			if opts.on_complete then
				opts.on_complete(nil, "Max iterations reached")
			end
			return
		end

		-- Determine system prompt and tools based on phase
		local system_prompt
		local tool_names

		if state.phase == "discovery" then
			local brain_context = brain.format_for_context(knowledge)
			system_prompt = planner.build_discovery_prompt(state.task, brain_context) .. rules
			tool_names = planner.get_discovery_tools()

			-- Add initial message if first iteration
			if #history == 0 then
				table.insert(history, { role = "system", content = system_prompt })
				table.insert(history, {
					role = "user",
					content = "Begin exploring the codebase to understand how to accomplish this task.",
				})
			end
		elseif state.phase == "planning" then
			system_prompt = planner.build_planning_prompt(state.task, table.concat(state.discovery_notes, "\n"))
				.. rules
			tool_names = planner.get_planning_tools()

			-- Reset history for planning phase
			if #history == 0 or history[1].content:match("DISCOVERY") then
				history = {}
				table.insert(history, { role = "system", content = system_prompt })
				table.insert(history, {
					role = "user",
					content = "Create a detailed implementation plan.",
				})
			end
		elseif state.phase == "execution" then
			if not state.plan then
				session.clear()
				if opts.on_complete then
					opts.on_complete(nil, "No approved plan for execution")
				end
				return
			end

			system_prompt = planner.build_execution_prompt(state.task, state.plan) .. rules
			tool_names = planner.get_execution_tools()

			-- Reset history for execution phase
			if #history == 0 or history[1].content:match("PLANNING") then
				history = {}
				table.insert(history, { role = "system", content = system_prompt })
				table.insert(history, {
					role = "user",
					content = "Begin executing the plan step by step.",
				})
			end
		else
			-- Complete - clear working memory but keep brain
			session.clear()
			memory.clear()

			if opts.on_status then
				opts.on_status(string.format("Complete! %s", brain.get_summary(knowledge)))
			end

			if opts.on_complete then
				opts.on_complete("Plan execution complete", nil)
			end
			return
		end

		if opts.on_status then
			opts.on_status(string.format("[%s] Thinking... (iteration %d)", state.phase, iteration))
		end

		-- Build tools for API
		local tools = build_tools(tool_names, provider)

		-- Build messages for API
		local messages = build_messages(history, provider)

		-- Call LLM
		call_llm(messages, tools, system_prompt, provider, opts.model, function(response, err)
			if err then
				session.clear()
				memory.clear()
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

			-- Handle phase-specific logic
			if state.phase == "discovery" then
				-- Track discoveries in working memory
				if content and content ~= "" then
					memory.add_discovery("general", content)
				end

				-- Check for discovery completion
				local discovery_summary = planner.parse_discovery_complete(content)
				if discovery_summary then
					table.insert(state.discovery_notes, discovery_summary)

					-- Extract and learn from discovery notes
					brain.extract_and_learn(knowledge, discovery_summary)

					-- Clear discoveries from working memory (keep only in brain)
					memory.clear_discoveries()

					planner.transition_phase(state, "planning")
					vim.schedule(process_iteration)
					return
				end
			elseif state.phase == "planning" then
				-- Check for plan creation
				local plan_steps = planner.parse_plan(content)
				if plan_steps then
					state.plan = planner.create_plan(state.task, table.concat(state.discovery_notes, "\n"), plan_steps)

					-- Store plan in working memory
					memory.set_plan(state.plan)

					-- Show plan for approval
					if opts.on_plan_ready then
						opts.on_plan_ready(state.plan)
					end

					-- For now, auto-approve (TODO: add UI for approval)
					state.plan.approved = true
					planner.transition_phase(state, "execution")
					vim.schedule(process_iteration)
					return
				end
			elseif state.phase == "execution" then
				-- Check if plan is complete
				local complete, completed, total = planner.is_plan_complete(state.plan)
				if complete then
					planner.transition_phase(state, "complete")
					vim.schedule(process_iteration)
					return
				end
			end

			-- Process tool calls if any
			if #tool_calls > 0 then
				for _, tc in ipairs(tool_calls) do
					local result, tool_err = execute_tool(tc, opts)

					-- In execution phase, track step progress
					if state.phase == "execution" and state.plan then
						local next_step = planner.get_next_step(state.plan)
						if next_step and not tool_err then
							planner.complete_step(state.plan, next_step.id, result, state.on_step_complete)
						elseif next_step and tool_err then
							planner.fail_step(state.plan, next_step.id, tool_err)
						end
					end

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
				-- No tool calls, continue if not explicitly complete
				if not is_complete(response, provider) then
					vim.schedule(process_iteration)
				else
					-- LLM says it's done, but check phase
					if state.phase == "execution" then
						-- Verify all steps are complete
						local complete = planner.is_plan_complete(state.plan)
						if complete then
							planner.transition_phase(state, "complete")
							vim.schedule(process_iteration)
						else
							-- Not all steps done, continue
							vim.schedule(process_iteration)
						end
					else
						-- In discovery/planning, keep going
						vim.schedule(process_iteration)
					end
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
