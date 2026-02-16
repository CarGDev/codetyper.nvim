---@mod codetyper.llm.copilot GitHub Copilot API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")
local llm = require("codetyper.core.llm")

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
	local credentials = require("codetyper.config.credentials")
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
	local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com") .. "/chat/completions"
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
				if
					response.error.code == "rate_limit_exceeded"
					or (error_msg:match("limit") and error_msg:match("plan"))
				then
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
				local cost = require("codetyper.core.cost")
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
	ensure_initialized()

	if not M.state.oauth_token then
		local err = "Copilot not authenticated. Please set up copilot.lua or copilot.vim first."
		callback(nil, err)
		return
	end

	refresh_token(function(token, err)
		if err then
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
			return
		end

		local body = build_request_body(prompt, context)
		utils.notify("Sending request to Copilot...", vim.log.levels.INFO)

		make_request(token, body, function(response, request_err, usage)
			if request_err then
				utils.notify(request_err, vim.log.levels.ERROR)
				callback(nil, request_err)
			else
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

return M
