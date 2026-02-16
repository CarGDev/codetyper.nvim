---@mod codetyper.llm.ollama Ollama API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")
local llm = require("codetyper.core.llm")

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
	local model = get_model()

	local body = build_request_body(prompt, context)
	utils.notify("Sending request to Ollama...", vim.log.levels.INFO)

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

return M
