---@mod codetyper.llm.ollama Ollama API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")
local llm = require("codetyper.llm")

--- Get Ollama host from stored credentials or config
---@return string Host URL
local function get_host()
	-- Priority: stored credentials > config
	local credentials = require("codetyper.credentials")
	local stored_host = credentials.get_ollama_host()
	if stored_host then
		return stored_host
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.ollama.host
end

--- Get model from stored credentials or config
---@return string Model name
local function get_model()
	-- Priority: stored credentials > config
	local credentials = require("codetyper.credentials")
	local stored_model = credentials.get_model("ollama")
	if stored_model then
		return stored_model
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.ollama.model
end

--- Build request body for Ollama API
---@param prompt string User prompt
---@param context table Context information
---@return table Request body
local function build_request_body(prompt, context)
	local system_prompt = llm.build_system_prompt(context)

	return {
		model = get_model(),
		system = system_prompt,
		prompt = prompt,
		stream = false,
		options = {
			temperature = 0.2,
			num_predict = 4096,
		},
	}
end

--- Make HTTP request to Ollama API
---@param body table Request body
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil) Callback function
local function make_request(body, callback)
	local host = get_host()
	local url = host .. "/api/generate"
	local json_body = vim.json.encode(body)

	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		url,
		"-H",
		"Content-Type: application/json",
		"-d",
		json_body,
	}

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data or #data == 0 or (data[1] == "" and #data == 1) then
				return
			end

			local response_text = table.concat(data, "\n")
			local ok, response = pcall(vim.json.decode, response_text)

			if not ok then
				vim.schedule(function()
					callback(nil, "Failed to parse Ollama response", nil)
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error or "Ollama API error", nil)
				end)
				return
			end

			-- Extract usage info
			local usage = {
				prompt_tokens = response.prompt_eval_count or 0,
				response_tokens = response.eval_count or 0,
			}

			if response.response then
				local code = llm.extract_code(response.response)
				vim.schedule(function()
					callback(code, nil, usage)
				end)
			else
				vim.schedule(function()
					callback(nil, "No response from Ollama", nil)
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Ollama API request failed: " .. table.concat(data, "\n"), nil)
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "Ollama API request failed with code: " .. code, nil)
				end)
			end
		end,
	})
end

--- Generate code using Ollama API
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
	local logs = require("codetyper.agent.logs")
	local model = get_model()

	-- Log the request
	logs.request("ollama", model)
	logs.thinking("Building request body...")

	local body = build_request_body(prompt, context)

	-- Estimate prompt tokens
	local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to Ollama API...")

	utils.notify("Sending request to Ollama...", vim.log.levels.INFO)

	make_request(body, function(response, err, usage)
		if err then
			logs.error(err)
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
		else
			-- Log token usage
			if usage then
				logs.response(usage.prompt_tokens or 0, usage.response_tokens or 0, "end_turn")
			end
			logs.thinking("Response received, extracting code...")
			logs.info("Code generated successfully")
			utils.notify("Code generated successfully", vim.log.levels.INFO)
			callback(response, nil)
		end
	end)
end

--- Check if Ollama is reachable
---@param callback fun(ok: boolean, error: string|nil) Callback function
function M.health_check(callback)
	local host = get_host()

	local cmd = { "curl", "-s", host .. "/api/tags" }

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(true, nil)
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(false, "Cannot connect to Ollama at " .. host)
				end)
			end
		end,
	})
end

--- Check if Ollama is properly configured
---@return boolean, string? Valid status and optional error message
function M.validate()
	local host = get_host()
	if not host or host == "" then
		return false, "Ollama host not configured"
	end
	local model = get_model()
	if not model or model == "" then
		return false, "Ollama model not configured"
	end
	return true
end

--- Generate with tool use support for agentic mode (text-based tool calling)
---@param messages table[] Conversation history
---@param context table Context information
---@param tool_definitions table Tool definitions
---@param callback fun(response: table|nil, error: string|nil) Callback with Claude-like response format
function M.generate_with_tools(messages, context, tool_definitions, callback)
	local logs = require("codetyper.agent.logs")
	local agent_prompts = require("codetyper.prompts.agent")
	local tools_module = require("codetyper.agent.tools")

	logs.request("ollama", get_model())
	logs.thinking("Preparing agent request...")

	-- Build system prompt with tool instructions
	local system_prompt = llm.build_system_prompt(context)
	system_prompt = system_prompt .. "\n\n" .. agent_prompts.system
	system_prompt = system_prompt .. "\n\n" .. agent_prompts.tool_instructions

	-- Add tool descriptions
	system_prompt = system_prompt .. "\n\n## Available Tools\n"
	system_prompt = system_prompt .. "Call tools by outputting JSON in this exact format:\n"
	system_prompt = system_prompt .. '```json\n{"tool": "tool_name", "arguments": {...}}\n```\n\n'

	for _, tool in ipairs(tool_definitions) do
		local name = tool.name or (tool["function"] and tool["function"].name)
		local desc = tool.description or (tool["function"] and tool["function"].description)
		if name then
			system_prompt = system_prompt .. string.format("### %s\n%s\n\n", name, desc or "")
		end
	end

	-- Convert messages to Ollama chat format
	local ollama_messages = {}
	for _, msg in ipairs(messages) do
		local content = msg.content
		if type(content) == "table" then
			local text_parts = {}
			for _, part in ipairs(content) do
				if part.type == "tool_result" then
					table.insert(text_parts, "[" .. (part.name or "tool") .. " result]: " .. (part.content or ""))
				elseif part.type == "text" then
					table.insert(text_parts, part.text or "")
				end
			end
			content = table.concat(text_parts, "\n")
		end
		table.insert(ollama_messages, { role = msg.role, content = content })
	end

	local body = {
		model = get_model(),
		messages = ollama_messages,
		system = system_prompt,
		stream = false,
		options = {
			temperature = 0.3,
			num_predict = 4096,
		},
	}

	local host = get_host()
	local url = host .. "/api/chat"
	local json_body = vim.json.encode(body)

	local prompt_estimate = logs.estimate_tokens(json_body)
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to Ollama API...")

	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		url,
		"-H",
		"Content-Type: application/json",
		"-d",
		json_body,
	}

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data or #data == 0 or (data[1] == "" and #data == 1) then
				return
			end

			local response_text = table.concat(data, "\n")
			local ok, response = pcall(vim.json.decode, response_text)

			if not ok then
				vim.schedule(function()
					logs.error("Failed to parse Ollama response")
					callback(nil, "Failed to parse Ollama response")
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					logs.error(response.error or "Ollama API error")
					callback(nil, response.error or "Ollama API error")
				end)
				return
			end

			-- Log token usage and record cost (Ollama is free but we track usage)
			if response.prompt_eval_count or response.eval_count then
				logs.response(response.prompt_eval_count or 0, response.eval_count or 0, "stop")

				-- Record usage for cost tracking (free for local models)
				local cost = require("codetyper.cost")
				cost.record_usage(
					get_model(),
					response.prompt_eval_count or 0,
					response.eval_count or 0,
					0 -- No cached tokens for Ollama
				)
			end

			-- Parse the response text for tool calls
			local content_text = response.message and response.message.content or ""
			local converted = { content = {}, stop_reason = "end_turn" }

			-- Try to extract JSON tool calls from response
			local json_match = content_text:match("```json%s*(%b{})%s*```")
			if json_match then
				local ok_json, parsed = pcall(vim.json.decode, json_match)
				if ok_json and parsed.tool then
					table.insert(converted.content, {
						type = "tool_use",
						id = "call_" .. string.format("%x", os.time()) .. "_" .. string.format("%x", math.random(0, 0xFFFF)),
						name = parsed.tool,
						input = parsed.arguments or {},
					})
					logs.thinking("Tool call: " .. parsed.tool)
					content_text = content_text:gsub("```json.-```", ""):gsub("^%s+", ""):gsub("%s+$", "")
					converted.stop_reason = "tool_use"
				end
			end

			-- Add text content
			if content_text and content_text ~= "" then
				table.insert(converted.content, 1, { type = "text", text = content_text })
				logs.thinking("Response contains text")
			end

			vim.schedule(function()
				callback(converted, nil)
			end)
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					logs.error("Ollama API request failed: " .. table.concat(data, "\n"))
					callback(nil, "Ollama API request failed: " .. table.concat(data, "\n"))
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					logs.error("Ollama API request failed with code: " .. code)
					callback(nil, "Ollama API request failed with code: " .. code)
				end)
			end
		end,
	})
end

return M
