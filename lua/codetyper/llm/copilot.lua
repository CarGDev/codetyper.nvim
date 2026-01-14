---@mod codetyper.llm.copilot GitHub Copilot API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")
local llm = require("codetyper.llm")

--- Copilot API endpoints
local AUTH_URL = "https://api.github.com/copilot_internal/v2/token"

--- Cached state
---@class CopilotState
---@field oauth_token string|nil
---@field github_token table|nil
M.state = nil

--- Get OAuth token from copilot.lua or copilot.vim config
---@return string|nil OAuth token
local function get_oauth_token()
	local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
	local os_name = vim.loop.os_uname().sysname:lower()

	local config_dir
	if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
		config_dir = xdg_config
	elseif os_name:match("linux") or os_name:match("darwin") then
		config_dir = vim.fn.expand("~/.config")
	else
		config_dir = vim.fn.expand("~/AppData/Local")
	end

	-- Try hosts.json (copilot.lua) and apps.json (copilot.vim)
	local paths = { "hosts.json", "apps.json" }
	for _, filename in ipairs(paths) do
		local path = config_dir .. "/github-copilot/" .. filename
		if vim.fn.filereadable(path) == 1 then
			local content = vim.fn.readfile(path)
			if content and #content > 0 then
				local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
				if ok and data then
					for key, value in pairs(data) do
						if key:match("github.com") and value.oauth_token then
							return value.oauth_token
						end
					end
				end
			end
		end
	end

	return nil
end

--- Get model from config
---@return string Model name
local function get_model()
	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	return config.llm.copilot.model
end

--- Refresh GitHub token using OAuth token
---@param callback fun(token: table|nil, error: string|nil)
local function refresh_token(callback)
	if not M.state or not M.state.oauth_token then
		callback(nil, "No OAuth token available")
		return
	end

	-- Check if current token is still valid
	if M.state.github_token and M.state.github_token.expires_at then
		if M.state.github_token.expires_at > os.time() then
			callback(M.state.github_token, nil)
			return
		end
	end

	local cmd = {
		"curl",
		"-s",
		"-X",
		"GET",
		AUTH_URL,
		"-H",
		"Authorization: token " .. M.state.oauth_token,
		"-H",
		"Accept: application/json",
	}

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data or #data == 0 or (data[1] == "" and #data == 1) then
				return
			end

			local response_text = table.concat(data, "\n")
			local ok, token = pcall(vim.json.decode, response_text)

			if not ok then
				vim.schedule(function()
					callback(nil, "Failed to parse token response")
				end)
				return
			end

			if token.error then
				vim.schedule(function()
					callback(nil, token.error_description or "Token refresh failed")
				end)
				return
			end

			M.state.github_token = token
			vim.schedule(function()
				callback(token, nil)
			end)
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Token refresh failed: " .. table.concat(data, "\n"))
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "Token refresh failed with code: " .. code)
				end)
			end
		end,
	})
end

--- Build request headers
---@param token table GitHub token
---@return table Headers
local function build_headers(token)
	return {
		"Authorization: Bearer " .. token.token,
		"Content-Type: application/json",
		"User-Agent: GitHubCopilotChat/0.26.7",
		"Editor-Version: vscode/1.105.1",
		"Editor-Plugin-Version: copilot-chat/0.26.7",
		"Copilot-Integration-Id: vscode-chat",
		"Openai-Intent: conversation-edits",
	}
end

--- Build request body for Copilot API
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
		stream = false,
	}
end

--- Make HTTP request to Copilot API
---@param token table GitHub token
---@param body table Request body
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil)
local function make_request(token, body, callback)
	local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com")
		.. "/chat/completions"
	local json_body = vim.json.encode(body)

	local headers = build_headers(token)
	local cmd = {
		"curl",
		"-s",
		"-X",
		"POST",
		endpoint,
	}

	for _, header in ipairs(headers) do
		table.insert(cmd, "-H")
		table.insert(cmd, header)
	end

	table.insert(cmd, "-d")
	table.insert(cmd, json_body)

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
					callback(nil, "Failed to parse Copilot response", nil)
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error.message or "Copilot API error", nil)
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
					callback(nil, "No content in Copilot response", nil)
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Copilot API request failed: " .. table.concat(data, "\n"), nil)
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "Copilot API request failed with code: " .. code, nil)
				end)
			end
		end,
	})
end

--- Initialize Copilot state
local function ensure_initialized()
	if not M.state then
		M.state = {
			oauth_token = get_oauth_token(),
			github_token = nil,
		}
	end
end

--- Generate code using Copilot API
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil)
function M.generate(prompt, context, callback)
	local logs = require("codetyper.agent.logs")

	ensure_initialized()

	if not M.state.oauth_token then
		local err = "Copilot not authenticated. Please set up copilot.lua or copilot.vim first."
		logs.error(err)
		callback(nil, err)
		return
	end

	local model = get_model()
	logs.request("copilot", model)
	logs.thinking("Refreshing authentication token...")

	refresh_token(function(token, err)
		if err then
			logs.error(err)
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
			return
		end

		logs.thinking("Building request body...")
		local body = build_request_body(prompt, context)

		local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
		logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
		logs.thinking("Sending to Copilot API...")

		utils.notify("Sending request to Copilot...", vim.log.levels.INFO)

		make_request(token, body, function(response, request_err, usage)
			if request_err then
				logs.error(request_err)
				utils.notify(request_err, vim.log.levels.ERROR)
				callback(nil, request_err)
			else
				if usage then
					logs.response(usage.prompt_tokens or 0, usage.completion_tokens or 0, "stop")
				end
				logs.thinking("Response received, extracting code...")
				logs.info("Code generated successfully")
				utils.notify("Code generated successfully", vim.log.levels.INFO)
				callback(response, nil)
			end
		end)
	end)
end

--- Check if Copilot is properly configured
---@return boolean, string? Valid status and optional error message
function M.validate()
	ensure_initialized()
	if not M.state.oauth_token then
		return false, "Copilot not authenticated. Set up copilot.lua or copilot.vim first."
	end
	return true
end

--- Generate with tool use support for agentic mode
---@param messages table[] Conversation history
---@param context table Context information
---@param tool_definitions table Tool definitions
---@param callback fun(response: table|nil, error: string|nil)
function M.generate_with_tools(messages, context, tool_definitions, callback)
	local logs = require("codetyper.agent.logs")

	ensure_initialized()

	if not M.state.oauth_token then
		local err = "Copilot not authenticated"
		logs.error(err)
		callback(nil, err)
		return
	end

	local model = get_model()
	logs.request("copilot", model)
	logs.thinking("Refreshing authentication token...")

	refresh_token(function(token, err)
		if err then
			logs.error(err)
			callback(nil, err)
			return
		end

		local tools_module = require("codetyper.agent.tools")
		local agent_prompts = require("codetyper.prompts.agent")

		-- Build system prompt with agent instructions
		local system_prompt = llm.build_system_prompt(context)
		system_prompt = system_prompt .. "\n\n" .. agent_prompts.system
		system_prompt = system_prompt .. "\n\n" .. agent_prompts.tool_instructions

		-- Format messages for Copilot (OpenAI-compatible format)
		local copilot_messages = { { role = "system", content = system_prompt } }
		for _, msg in ipairs(messages) do
			if type(msg.content) == "string" then
				table.insert(copilot_messages, { role = msg.role, content = msg.content })
			elseif type(msg.content) == "table" then
				local text_parts = {}
				for _, part in ipairs(msg.content) do
					if part.type == "tool_result" then
						table.insert(text_parts, "[" .. (part.name or "tool") .. " result]: " .. (part.content or ""))
					elseif part.type == "text" then
						table.insert(text_parts, part.text or "")
					end
				end
				if #text_parts > 0 then
					table.insert(copilot_messages, { role = msg.role, content = table.concat(text_parts, "\n") })
				end
			end
		end

		local body = {
			model = get_model(),
			messages = copilot_messages,
			max_tokens = 4096,
			temperature = 0.3,
			stream = false,
			tools = tools_module.to_openai_format(),
		}

		local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com")
			.. "/chat/completions"
		local json_body = vim.json.encode(body)

		local prompt_estimate = logs.estimate_tokens(json_body)
		logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
		logs.thinking("Sending to Copilot API...")

		local headers = build_headers(token)
		local cmd = {
			"curl",
			"-s",
			"-X",
			"POST",
			endpoint,
		}

		for _, header in ipairs(headers) do
			table.insert(cmd, "-H")
			table.insert(cmd, header)
		end

		table.insert(cmd, "-d")
		table.insert(cmd, json_body)

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
						logs.error("Failed to parse Copilot response")
						callback(nil, "Failed to parse Copilot response")
					end)
					return
				end

				if response.error then
					vim.schedule(function()
						logs.error(response.error.message or "Copilot API error")
						callback(nil, response.error.message or "Copilot API error")
					end)
					return
				end

				-- Log token usage
				if response.usage then
					logs.response(response.usage.prompt_tokens or 0, response.usage.completion_tokens or 0, "stop")
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
						logs.error("Copilot API request failed: " .. table.concat(data, "\n"))
						callback(nil, "Copilot API request failed: " .. table.concat(data, "\n"))
					end)
				end
			end,
			on_exit = function(_, code)
				if code ~= 0 then
					vim.schedule(function()
						logs.error("Copilot API request failed with code: " .. code)
						callback(nil, "Copilot API request failed with code: " .. code)
					end)
				end
			end,
		})
	end)
end

return M
