---@mod codetyper.llm.gemini Google Gemini API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")
local llm = require("codetyper.core.llm")

--- Gemini API endpoint
local API_URL = "https://generativelanguage.googleapis.com/v1beta/models"

--- Get API key from stored credentials, config, or environment
---@return string|nil API key
local function get_api_key()
	-- Priority: stored credentials > config > environment
	local credentials = require("codetyper.credentials")
	local stored_key = credentials.get_api_key("gemini")
	if stored_key then
		return stored_key
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.gemini.api_key or vim.env.GEMINI_API_KEY
end

--- Get model from stored credentials or config
---@return string Model name
local function get_model()
	-- Priority: stored credentials > config
	local credentials = require("codetyper.credentials")
	local stored_model = credentials.get_model("gemini")
	if stored_model then
		return stored_model
	end

	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.gemini.model
end

--- Build request body for Gemini API
---@param prompt string User prompt
---@param context table Context information
---@return table Request body
local function build_request_body(prompt, context)
	local system_prompt = llm.build_system_prompt(context)

	return {
		systemInstruction = {
			role = "user",
			parts = { { text = system_prompt } },
		},
		contents = {
			{
				role = "user",
				parts = { { text = prompt } },
			},
		},
		generationConfig = {
			temperature = 0.2,
			maxOutputTokens = 4096,
		},
	}
end

--- Make HTTP request to Gemini API
---@param body table Request body
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil) Callback function
local function make_request(body, callback)
	local api_key = get_api_key()
	if not api_key then
		callback(nil, "Gemini API key not configured", nil)
		return
	end

	local model = get_model()
	local url = API_URL .. "/" .. model .. ":generateContent?key=" .. api_key
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
					callback(nil, "Failed to parse Gemini response", nil)
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error.message or "Gemini API error", nil)
				end)
				return
			end

			-- Extract usage info
			local usage = {}
			if response.usageMetadata then
				usage.prompt_tokens = response.usageMetadata.promptTokenCount or 0
				usage.completion_tokens = response.usageMetadata.candidatesTokenCount or 0
			end

			if response.candidates and response.candidates[1] then
				local candidate = response.candidates[1]
				if candidate.content and candidate.content.parts then
					local text_parts = {}
					for _, part in ipairs(candidate.content.parts) do
						if part.text then
							table.insert(text_parts, part.text)
						end
					end
					local full_text = table.concat(text_parts, "")
					local code = llm.extract_code(full_text)
					vim.schedule(function()
						callback(code, nil, usage)
					end)
				else
					vim.schedule(function()
						callback(nil, "No content in Gemini response", nil)
					end)
				end
			else
				vim.schedule(function()
					callback(nil, "No candidates in Gemini response", nil)
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Gemini API request failed: " .. table.concat(data, "\n"), nil)
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "Gemini API request failed with code: " .. code, nil)
				end)
			end
		end,
	})
end

--- Generate code using Gemini API
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
	local logs = require("codetyper.adapters.nvim.ui.logs")
	local model = get_model()

	-- Log the request
	logs.request("gemini", model)
	logs.thinking("Building request body...")

	local body = build_request_body(prompt, context)

	-- Estimate prompt tokens
	local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to Gemini API...")

	utils.notify("Sending request to Gemini...", vim.log.levels.INFO)

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

--- Check if Gemini is properly configured
---@return boolean, string? Valid status and optional error message
function M.validate()
	local api_key = get_api_key()
	if not api_key or api_key == "" then
		return false, "Gemini API key not configured"
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

	logs.request("gemini", model)
	logs.thinking("Preparing agent request...")

	local api_key = get_api_key()
	if not api_key then
		logs.error("Gemini API key not configured")
		callback(nil, "Gemini API key not configured")
		return
	end

	local tools_module = require("codetyper.core.tools")
	local agent_prompts = require("codetyper.prompts.agents")

	-- Build system prompt with agent instructions
	local system_prompt = llm.build_system_prompt(context)
	system_prompt = system_prompt .. "\n\n" .. agent_prompts.system
	system_prompt = system_prompt .. "\n\n" .. agent_prompts.tool_instructions

	-- Format messages for Gemini
	local gemini_contents = {}
	for _, msg in ipairs(messages) do
		local role = msg.role == "assistant" and "model" or "user"
		local parts = {}

		if type(msg.content) == "string" then
			table.insert(parts, { text = msg.content })
		elseif type(msg.content) == "table" then
			for _, part in ipairs(msg.content) do
				if part.type == "tool_result" then
					table.insert(parts, { text = "[" .. (part.name or "tool") .. " result]: " .. (part.content or "") })
				elseif part.type == "text" then
					table.insert(parts, { text = part.text or "" })
				end
			end
		end

		if #parts > 0 then
			table.insert(gemini_contents, { role = role, parts = parts })
		end
	end

	-- Build function declarations for tools
	local function_declarations = {}
	for _, tool in ipairs(tools_module.definitions) do
		local properties = {}
		local required = {}

		if tool.parameters and tool.parameters.properties then
			for name, prop in pairs(tool.parameters.properties) do
				properties[name] = {
					type = prop.type:upper(),
					description = prop.description,
				}
			end
		end

		if tool.parameters and tool.parameters.required then
			required = tool.parameters.required
		end

		table.insert(function_declarations, {
			name = tool.name,
			description = tool.description,
			parameters = {
				type = "OBJECT",
				properties = properties,
				required = required,
			},
		})
	end

	local body = {
		systemInstruction = {
			role = "user",
			parts = { { text = system_prompt } },
		},
		contents = gemini_contents,
		generationConfig = {
			temperature = 0.3,
			maxOutputTokens = 4096,
		},
		tools = {
			{ functionDeclarations = function_declarations },
		},
	}

	local url = API_URL .. "/" .. model .. ":generateContent?key=" .. api_key
	local json_body = vim.json.encode(body)

	local prompt_estimate = logs.estimate_tokens(json_body)
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to Gemini API...")

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
					logs.error("Failed to parse Gemini response")
					callback(nil, "Failed to parse Gemini response")
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					logs.error(response.error.message or "Gemini API error")
					callback(nil, response.error.message or "Gemini API error")
				end)
				return
			end

			-- Log token usage
			if response.usageMetadata then
				logs.response(
					response.usageMetadata.promptTokenCount or 0,
					response.usageMetadata.candidatesTokenCount or 0,
					"stop"
				)
			end

			-- Convert to Claude-like format for parser compatibility
			local converted = { content = {} }
			if response.candidates and response.candidates[1] then
				local candidate = response.candidates[1]
				if candidate.content and candidate.content.parts then
					for _, part in ipairs(candidate.content.parts) do
						if part.text then
							table.insert(converted.content, { type = "text", text = part.text })
							logs.thinking("Response contains text")
						elseif part.functionCall then
							table.insert(converted.content, {
								type = "tool_use",
								id = vim.fn.sha256(vim.json.encode(part.functionCall)):sub(1, 16),
								name = part.functionCall.name,
								input = part.functionCall.args or {},
							})
							logs.thinking("Tool call: " .. part.functionCall.name)
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
					logs.error("Gemini API request failed: " .. table.concat(data, "\n"))
					callback(nil, "Gemini API request failed: " .. table.concat(data, "\n"))
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					logs.error("Gemini API request failed with code: " .. code)
					callback(nil, "Gemini API request failed with code: " .. code)
				end)
			end
		end,
	})
end

return M
