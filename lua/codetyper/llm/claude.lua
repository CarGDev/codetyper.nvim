---@mod codetyper.llm.claude Claude API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")
local llm = require("codetyper.llm")

--- Claude API endpoint
local API_URL = "https://api.anthropic.com/v1/messages"

--- Get API key from config or environment
---@return string|nil API key
local function get_api_key()
	local codetyper = require("codetyper")
	local config = codetyper.get_config()

	return config.llm.claude.api_key or vim.env.ANTHROPIC_API_KEY
end

--- Get model from config
---@return string Model name
local function get_model()
	local codetyper = require("codetyper")
	local config = codetyper.get_config()

	return config.llm.claude.model
end

--- Build request body for Claude API
---@param prompt string User prompt
---@param context table Context information
---@return table Request body
local function build_request_body(prompt, context)
	local system_prompt = llm.build_system_prompt(context)

	return {
		model = get_model(),
		max_tokens = 4096,
		system = system_prompt,
		messages = {
			{
				role = "user",
				content = prompt,
			},
		},
	}
end

--- Make HTTP request to Claude API
---@param body table Request body
---@param callback fun(response: string|nil, error: string|nil) Callback function
local function make_request(body, callback)
	local api_key = get_api_key()
	if not api_key then
		callback(nil, "Claude API key not configured")
		return
	end

	local json_body = vim.json.encode(body)

	-- Use curl for HTTP request (plenary.curl alternative)
	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		API_URL,
		"-H",
		"Content-Type: application/json",
		"-H",
		"x-api-key: " .. api_key,
		"-H",
		"anthropic-version: 2023-06-01",
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
					callback(nil, "Failed to parse Claude response")
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error.message or "Claude API error")
				end)
				return
			end

			if response.content and response.content[1] and response.content[1].text then
				local code = llm.extract_code(response.content[1].text)
				vim.schedule(function()
					callback(code, nil)
				end)
			else
				vim.schedule(function()
					callback(nil, "No content in Claude response")
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Claude API request failed: " .. table.concat(data, "\n"))
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "Claude API request failed with code: " .. code)
				end)
			end
		end,
	})
end

--- Generate code using Claude API
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
	utils.notify("Sending request to Claude...", vim.log.levels.INFO)

	local body = build_request_body(prompt, context)
	make_request(body, function(response, err)
		if err then
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
		else
			utils.notify("Code generated successfully", vim.log.levels.INFO)
			callback(response, nil)
		end
	end)
end

--- Check if Claude is properly configured
---@return boolean, string? Valid status and optional error message
function M.validate()
	local api_key = get_api_key()
	if not api_key or api_key == "" then
		return false, "Claude API key not configured"
	end
	return true
end

--- Build request body for Claude API with tools
---@param messages table[] Conversation messages
---@param context table Context information
---@param tools table Tool definitions
---@return table Request body
local function build_tools_request_body(messages, context, tools)
	local agent_prompts = require("codetyper.prompts.agent")
	local tools_module = require("codetyper.agent.tools")

	-- Build system prompt for agent mode
	local system_prompt = agent_prompts.system

	-- Add context about current file if available
	if context.file_path then
		system_prompt = system_prompt .. "\n\nCurrent working context:\n"
		system_prompt = system_prompt .. "- File: " .. context.file_path .. "\n"
		if context.language then
			system_prompt = system_prompt .. "- Language: " .. context.language .. "\n"
		end
	end

	-- Add project root info
	local utils = require("codetyper.utils")
	local root = utils.get_project_root()
	if root then
		system_prompt = system_prompt .. "- Project root: " .. root .. "\n"
	end

	return {
		model = get_model(),
		max_tokens = 4096,
		system = system_prompt,
		messages = messages,
		tools = tools_module.to_claude_format(),
	}
end

--- Make HTTP request to Claude API for tool use
---@param body table Request body
---@param callback fun(response: table|nil, error: string|nil) Callback function
local function make_tools_request(body, callback)
	local api_key = get_api_key()
	if not api_key then
		callback(nil, "Claude API key not configured")
		return
	end

	local json_body = vim.json.encode(body)

	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		API_URL,
		"-H",
		"Content-Type: application/json",
		"-H",
		"x-api-key: " .. api_key,
		"-H",
		"anthropic-version: 2023-06-01",
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
					callback(nil, "Failed to parse Claude response")
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error.message or "Claude API error")
				end)
				return
			end

			-- Return the full response for tool parsing
			vim.schedule(function()
				callback(response, nil)
			end)
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Claude API request failed: " .. table.concat(data, "\n"))
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				-- Only report if no response was received
				-- (curl may return non-zero even with successful response in some cases)
			end
		end,
	})
end

--- Generate response with tools using Claude API
---@param messages table[] Conversation history
---@param context table Context information
---@param tools table Tool definitions (ignored, we use our own)
---@param callback fun(response: table|nil, error: string|nil) Callback function
function M.generate_with_tools(messages, context, tools, callback)
	local logs = require("codetyper.agent.logs")

	-- Log the request
	local model = get_model()
	logs.request("claude", model)
	logs.thinking("Preparing API request...")

	local body = build_tools_request_body(messages, context, tools)

	-- Estimate prompt tokens
	local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))

	make_tools_request(body, function(response, err)
		if err then
			logs.error(err)
			callback(nil, err)
		else
			-- Log token usage from response
			if response and response.usage then
				logs.response(
					response.usage.input_tokens or 0,
					response.usage.output_tokens or 0,
					response.stop_reason
				)
			end

			-- Log what's in the response
			if response and response.content then
				local has_text = false
				local has_tools = false
				for _, block in ipairs(response.content) do
					if block.type == "text" then
						has_text = true
					elseif block.type == "tool_use" then
						has_tools = true
						logs.thinking("Tool call: " .. block.name)
					end
				end
				if has_text then
					logs.thinking("Response contains text")
				end
				if has_tools then
					logs.thinking("Response contains tool calls")
				end
			end

			callback(response, nil)
		end
	end)
end

return M
