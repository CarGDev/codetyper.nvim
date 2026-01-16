---@mod codetyper.llm.openai OpenAI API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")
local llm = require("codetyper.core.llm")

--- OpenAI API endpoint
local API_URL = "https://api.openai.com/v1/chat/completions"

--- Get API key from stored credentials, config, or environment
---@return string|nil API key
local function get_api_key()
	-- Priority: stored credentials > config > environment
	local credentials = require("codetyper.credentials")
	local stored_key = credentials.get_api_key("openai")
	if stored_key then
		return stored_key
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.openai.api_key or vim.env.OPENAI_API_KEY
end

--- Get model from stored credentials or config
---@return string Model name
local function get_model()
	-- Priority: stored credentials > config
	local credentials = require("codetyper.credentials")
	local stored_model = credentials.get_model("openai")
	if stored_model then
		return stored_model
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.openai.model
end

--- Get endpoint from stored credentials or config (allows custom endpoints like Azure, OpenRouter)
---@return string API endpoint
local function get_endpoint()
	-- Priority: stored credentials > config > default
	local credentials = require("codetyper.credentials")
	local stored_endpoint = credentials.get_endpoint("openai")
	if stored_endpoint then
		return stored_endpoint
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.openai.endpoint or API_URL
end

--- Build request body for OpenAI API
---@param prompt string User prompt
---@param context table Context information
---@return table Request body
local function build_request_body(prompt, context)
	local system_prompt = llm.build_system_prompt(context)

	return {
		model = get_model(),
		messages = {
			{ role = "system", content = system_prompt },
			{ role = "user", content = prompt },
		},
		max_tokens = 4096,
		temperature = 0.2,
	}
end

--- Make HTTP request to OpenAI API
---@param body table Request body
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil) Callback function
local function make_request(body, callback)
	local api_key = get_api_key()
	if not api_key then
		callback(nil, "OpenAI API key not configured", nil)
		return
	end

	local endpoint = get_endpoint()
	local json_body = vim.json.encode(body)

	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		endpoint,
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. api_key,
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
					callback(nil, "Failed to parse OpenAI response", nil)
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error.message or "OpenAI API error", nil)
				end)
				return
			end

			-- Extract usage info
			local usage = response.usage or {}

			if response.choices and response.choices[1] and response.choices[1].message then
				local code = llm.extract_code(response.choices[1].message.content)
				vim.schedule(function()
					callback(code, nil, usage)
				end)
			else
				vim.schedule(function()
					callback(nil, "No content in OpenAI response", nil)
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "OpenAI API request failed: " .. table.concat(data, "\n"), nil)
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "OpenAI API request failed with code: " .. code, nil)
				end)
			end
		end,
	})
end

--- Generate code using OpenAI API
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
	local logs = require("codetyper.adapters.nvim.ui.logs")
	local model = get_model()

	-- Log the request
	logs.request("openai", model)
	logs.thinking("Building request body...")

	local body = build_request_body(prompt, context)

	-- Estimate prompt tokens
	local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to OpenAI API...")

	utils.notify("Sending request to OpenAI...", vim.log.levels.INFO)

	make_request(body, function(response, err, usage)
		if err then
			logs.error(err)
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
		else
			-- Log token usage
			if usage then
				logs.response(usage.prompt_tokens or 0, usage.completion_tokens or 0, "stop")
			end
			logs.thinking("Response received, extracting code...")
			logs.info("Code generated successfully")
			utils.notify("Code generated successfully", vim.log.levels.INFO)
			callback(response, nil)
		end
	end)
end

--- Check if OpenAI is properly configured
---@return boolean, string? Valid status and optional error message
function M.validate()
	local api_key = get_api_key()
	if not api_key or api_key == "" then
		return false, "OpenAI API key not configured"
	end
	return true
end

--- Generate with tool use support for agentic mode
---@param messages table[] Conversation history
---@param context table Context information
---@param tool_definitions table Tool definitions
---@param callback fun(response: table|nil, error: string|nil) Callback with raw response
function M.generate_with_tools(messages, context, tool_definitions, callback)
	local logs = require("codetyper.adapters.nvim.ui.logs")
	local model = get_model()

	logs.request("openai", model)
	logs.thinking("Preparing agent request...")

	local api_key = get_api_key()
	if not api_key then
		logs.error("OpenAI API key not configured")
		callback(nil, "OpenAI API key not configured")
		return
	end

	local tools_module = require("codetyper.core.tools")
	local agent_prompts = require("codetyper.prompts.agent")

	-- Build system prompt with agent instructions
	local system_prompt = llm.build_system_prompt(context)
	system_prompt = system_prompt .. "\n\n" .. agent_prompts.system
	system_prompt = system_prompt .. "\n\n" .. agent_prompts.tool_instructions

	-- Format messages for OpenAI
	local openai_messages = { { role = "system", content = system_prompt } }
	for _, msg in ipairs(messages) do
		if type(msg.content) == "string" then
			table.insert(openai_messages, { role = msg.role, content = msg.content })
		elseif type(msg.content) == "table" then
			-- Handle tool results
			local text_parts = {}
			for _, part in ipairs(msg.content) do
				if part.type == "tool_result" then
					table.insert(text_parts, "[" .. (part.name or "tool") .. " result]: " .. (part.content or ""))
				elseif part.type == "text" then
					table.insert(text_parts, part.text or "")
				end
			end
			if #text_parts > 0 then
				table.insert(openai_messages, { role = msg.role, content = table.concat(text_parts, "\n") })
			end
		end
	end

	local body = {
		model = get_model(),
		messages = openai_messages,
		max_tokens = 4096,
		temperature = 0.3,
		tools = tools_module.to_openai_format(),
	}

	local endpoint = get_endpoint()
	local json_body = vim.json.encode(body)

	local prompt_estimate = logs.estimate_tokens(json_body)
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to OpenAI API...")

	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		endpoint,
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. api_key,
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
					logs.error("Failed to parse OpenAI response")
					callback(nil, "Failed to parse OpenAI response")
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					logs.error(response.error.message or "OpenAI API error")
					callback(nil, response.error.message or "OpenAI API error")
				end)
				return
			end

			-- Log token usage and record cost
			if response.usage then
				logs.response(response.usage.prompt_tokens or 0, response.usage.completion_tokens or 0, "stop")

				-- Record usage for cost tracking
				local cost = require("codetyper.core.cost")
				cost.record_usage(
					model,
					response.usage.prompt_tokens or 0,
					response.usage.completion_tokens or 0,
					response.usage.prompt_tokens_details and response.usage.prompt_tokens_details.cached_tokens or 0
				)
			end

			-- Convert to Claude-like format for parser compatibility
			local converted = { content = {} }
			if response.choices and response.choices[1] then
				local choice = response.choices[1]
				if choice.message then
					if choice.message.content then
						table.insert(converted.content, { type = "text", text = choice.message.content })
						logs.thinking("Response contains text")
					end
					if choice.message.tool_calls then
						for _, tc in ipairs(choice.message.tool_calls) do
							local args = {}
							if tc["function"] and tc["function"].arguments then
								local ok_args, parsed = pcall(vim.json.decode, tc["function"].arguments)
								if ok_args then
									args = parsed
								end
							end
							table.insert(converted.content, {
								type = "tool_use",
								id = tc.id,
								name = tc["function"].name,
								input = args,
							})
							logs.thinking("Tool call: " .. tc["function"].name)
						end
					end
				end
			end

			vim.schedule(function()
				callback(converted, nil)
			end)
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					logs.error("OpenAI API request failed: " .. table.concat(data, "\n"))
					callback(nil, "OpenAI API request failed: " .. table.concat(data, "\n"))
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					logs.error("OpenAI API request failed with code: " .. code)
					callback(nil, "OpenAI API request failed with code: " .. code)
				end)
			end
		end,
	})
end

return M
