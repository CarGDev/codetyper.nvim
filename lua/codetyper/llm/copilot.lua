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

--- Track if we've already suggested Ollama fallback this session
local ollama_fallback_suggested = false

--- Suggest switching to Ollama when rate limits are hit
---@param error_msg string The error message that triggered this
function M.suggest_ollama_fallback(error_msg)
	if ollama_fallback_suggested then
		return
	end

	-- Check if Ollama is available
	local ollama_available = false
	vim.fn.jobstart({ "curl", "-s", "http://localhost:11434/api/tags" }, {
		on_exit = function(_, code)
			if code == 0 then
				ollama_available = true
			end

			vim.schedule(function()
				if ollama_available then
					-- Switch to Ollama automatically
					local codetyper = require("codetyper")
					local config = codetyper.get_config()
					config.llm.provider = "ollama"

					ollama_fallback_suggested = true
					utils.notify(
						"⚠️ Copilot rate limit reached. Switched to Ollama automatically.\n"
							.. "Original error: "
							.. error_msg:sub(1, 100),
						vim.log.levels.WARN
					)
				else
					utils.notify(
						"⚠️ Copilot rate limit reached. Ollama not available.\n"
							.. "Start Ollama with: ollama serve\n"
							.. "Or wait for Copilot limits to reset.",
						vim.log.levels.WARN
					)
				end
			end)
		end,
	})
end

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

--- Get model from stored credentials or config
---@return string Model name
local function get_model()
	-- Priority: stored credentials > config
	local credentials = require("codetyper.credentials")
	local stored_model = credentials.get_model("copilot")
	if stored_model then
		return stored_model
	end

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
				-- Show the actual response text as the error (truncated if too long)
				local error_msg = response_text
				if #error_msg > 200 then
					error_msg = error_msg:sub(1, 200) .. "..."
				end

				-- Clean up common patterns
				if response_text:match("<!DOCTYPE") or response_text:match("<html") then
					error_msg = "Copilot API returned HTML error page. Service may be unavailable."
				end

				-- Check for rate limit and suggest Ollama fallback
				if response_text:match("limit") or response_text:match("Upgrade") or response_text:match("quota") then
					M.suggest_ollama_fallback(error_msg)
				end

				vim.schedule(function()
					callback(nil, error_msg, nil)
				end)
				return
			end

			if response.error then
				local error_msg = response.error.message or "Copilot API error"
				if response.error.code == "rate_limit_exceeded" or (error_msg:match("limit") and error_msg:match("plan")) then
					error_msg = "Copilot rate limit: " .. error_msg
					M.suggest_ollama_fallback(error_msg)
				end

				vim.schedule(function()
					callback(nil, error_msg, nil)
				end)
				return
			end

			-- Extract usage info
			local usage = response.usage or {}

			-- Record usage for cost tracking
			if usage.prompt_tokens or usage.completion_tokens then
				local cost = require("codetyper.cost")
				cost.record_usage(
					get_model(),
					usage.prompt_tokens or 0,
					usage.completion_tokens or 0,
					usage.prompt_tokens_details and usage.prompt_tokens_details.cached_tokens or 0
				)
			end

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
			if msg.role == "user" then
				-- User messages - handle string or table content
				if type(msg.content) == "string" then
					table.insert(copilot_messages, { role = "user", content = msg.content })
				elseif type(msg.content) == "table" then
					-- Handle complex content (like tool results from user perspective)
					local text_parts = {}
					for _, part in ipairs(msg.content) do
						if part.type == "tool_result" then
							table.insert(text_parts, "[" .. (part.name or "tool") .. " result]: " .. (part.content or ""))
						elseif part.type == "text" then
							table.insert(text_parts, part.text or "")
						end
					end
					if #text_parts > 0 then
						table.insert(copilot_messages, { role = "user", content = table.concat(text_parts, "\n") })
					end
				end
			elseif msg.role == "assistant" then
				-- Assistant messages - must preserve tool_calls if present
				local assistant_msg = {
					role = "assistant",
					content = type(msg.content) == "string" and msg.content or nil,
				}
				-- Preserve tool_calls for the API
				if msg.tool_calls then
					assistant_msg.tool_calls = msg.tool_calls
					-- Ensure content is not nil when tool_calls present
					if assistant_msg.content == nil then
						assistant_msg.content = ""
					end
				end
				table.insert(copilot_messages, assistant_msg)
			elseif msg.role == "tool" then
				-- Tool result messages - must have tool_call_id
				table.insert(copilot_messages, {
					role = "tool",
					tool_call_id = msg.tool_call_id,
					content = type(msg.content) == "string" and msg.content or vim.json.encode(msg.content),
				})
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

		-- Log request to debug file
		local debug_log_path = vim.fn.expand("~/.local/codetyper-debug.log")
		local debug_f = io.open(debug_log_path, "a")
		if debug_f then
			debug_f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. "COPILOT REQUEST\n")
			debug_f:write("Messages count: " .. #copilot_messages .. "\n")
			for i, m in ipairs(copilot_messages) do
				debug_f:write(string.format("  [%d] role=%s, has_tool_calls=%s, has_tool_call_id=%s\n",
					i, m.role, tostring(m.tool_calls ~= nil), tostring(m.tool_call_id ~= nil)))
			end
			debug_f:write("---\n")
			debug_f:close()
		end

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

		-- Debug logging helper
		local function debug_log(msg, data)
			local log_path = vim.fn.expand("~/.local/codetyper-debug.log")
			local f = io.open(log_path, "a")
			if f then
				f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg .. "\n")
				if data then
					f:write("DATA: " .. tostring(data):sub(1, 2000) .. "\n")
				end
				f:write("---\n")
				f:close()
			end
		end

		-- Prevent double callback calls
		local callback_called = false

		vim.fn.jobstart(cmd, {
			stdout_buffered = true,
			on_stdout = function(_, data)
				if callback_called then
					debug_log("on_stdout: callback already called, skipping")
					return
				end

				if not data or #data == 0 or (data[1] == "" and #data == 1) then
					debug_log("on_stdout: empty data")
					return
				end

				local response_text = table.concat(data, "\n")
				debug_log("on_stdout: received response", response_text)

				local ok, response = pcall(vim.json.decode, response_text)

				if not ok then
					debug_log("JSON parse failed", response_text)
					callback_called = true

					-- Show the actual response text as the error (truncated if too long)
					local error_msg = response_text
					if #error_msg > 200 then
						error_msg = error_msg:sub(1, 200) .. "..."
					end

					-- Clean up common patterns
					if response_text:match("<!DOCTYPE") or response_text:match("<html") then
						error_msg = "Copilot API returned HTML error page. Service may be unavailable."
					end

					-- Check for rate limit and suggest Ollama fallback
					if response_text:match("limit") or response_text:match("Upgrade") or response_text:match("quota") then
						M.suggest_ollama_fallback(error_msg)
					end

					vim.schedule(function()
						logs.error(error_msg)
						callback(nil, error_msg)
					end)
					return
				end

				if response.error then
					callback_called = true
					local error_msg = response.error.message or "Copilot API error"

					-- Check for rate limit in structured error
					if response.error.code == "rate_limit_exceeded" or (error_msg:match("limit") and error_msg:match("plan")) then
						error_msg = "Copilot rate limit: " .. error_msg
						M.suggest_ollama_fallback(error_msg)
					end

					vim.schedule(function()
						logs.error(error_msg)
						callback(nil, error_msg)
					end)
					return
				end

				-- Log token usage and record cost
				if response.usage then
					logs.response(response.usage.prompt_tokens or 0, response.usage.completion_tokens or 0, "stop")

					-- Record usage for cost tracking
					local cost_tracker = require("codetyper.cost")
					cost_tracker.record_usage(
						get_model(),
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

				callback_called = true
				debug_log("on_stdout: success, calling callback")
				vim.schedule(function()
					callback(converted, nil)
				end)
			end,
			on_stderr = function(_, data)
				if callback_called then
					return
				end
				if data and #data > 0 and data[1] ~= "" then
					debug_log("on_stderr", table.concat(data, "\n"))
					callback_called = true
					vim.schedule(function()
						logs.error("Copilot API request failed: " .. table.concat(data, "\n"))
						callback(nil, "Copilot API request failed: " .. table.concat(data, "\n"))
					end)
				end
			end,
			on_exit = function(_, code)
				debug_log("on_exit: code=" .. code .. ", callback_called=" .. tostring(callback_called))
				if callback_called then
					return
				end
				if code ~= 0 then
					callback_called = true
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
