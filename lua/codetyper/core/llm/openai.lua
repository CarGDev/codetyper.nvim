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
	local body = build_request_body(prompt, context)
	utils.notify("Sending request to OpenAI...", vim.log.levels.INFO)

	make_request(body, function(response, err, usage)
		if err then
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
		else
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

return M
