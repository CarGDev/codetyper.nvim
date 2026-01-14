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
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil) Callback function
local function make_request(body, callback)
	local api_key = get_api_key()
	if not api_key then
		callback(nil, "Claude API key not configured", nil)
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
					callback(nil, "Failed to parse Claude response", nil)
				end)
				return
			end

			if response.error then
				vim.schedule(function()
					callback(nil, response.error.message or "Claude API error", nil)
				end)
				return
			end

			-- Extract usage info
			local usage = response.usage or {}

			if response.content and response.content[1] and response.content[1].text then
				local code = llm.extract_code(response.content[1].text)
				vim.schedule(function()
					callback(code, nil, usage)
				end)
			else
				vim.schedule(function()
					callback(nil, "No content in Claude response", nil)
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" then
				vim.schedule(function()
					callback(nil, "Claude API request failed: " .. table.concat(data, "\n"), nil)
				end)
			end
		end,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					callback(nil, "Claude API request failed with code: " .. code, nil)
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
	local logs = require("codetyper.agent.logs")
	local model = get_model()

	-- Log the request
	logs.request("claude", model)
	logs.thinking("Building request body...")

	local body = build_request_body(prompt, context)

	-- Estimate prompt tokens
	local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
	logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
	logs.thinking("Sending to Claude API...")

	utils.notify("Sending request to Claude...", vim.log.levels.INFO)

	make_request(body, function(response, err, usage)
		if err then
			logs.error(err)
			utils.notify(err, vim.log.levels.ERROR)
			callback(nil, err)
		else
			-- Log token usage
			if usage then
				logs.response(
					usage.input_tokens or 0,
					usage.output_tokens or 0,
					"end_turn"
				)
			end
			logs.thinking("Response received, extracting code...")
			logs.info("Code generated successfully")
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

--- Generate with tool use support for agentic mode
---@param messages table[] Conversation history
---@param context table Context information
---@param tool_definitions table Tool definitions
---@param callback fun(response: table|nil, error: string|nil) Callback with raw response
function M.generate_with_tools(messages, context, tool_definitions, callback)
  local logs = require("codetyper.agent.logs")
  local model = get_model()

  -- Log the request
  logs.request("claude", model)
  logs.thinking("Preparing agent request...")

  local api_key = get_api_key()
  if not api_key then
    logs.error("Claude API key not configured")
    callback(nil, "Claude API key not configured")
    return
  end

  local tools_module = require("codetyper.agent.tools")
  local agent_prompts = require("codetyper.prompts.agent")

  -- Build system prompt with agent instructions
  local system_prompt = llm.build_system_prompt(context)
  system_prompt = system_prompt .. "\n\n" .. agent_prompts.system
  system_prompt = system_prompt .. "\n\n" .. agent_prompts.tool_instructions

  -- Build request body with tools
  local body = {
    model = get_model(),
    max_tokens = 4096,
    system = system_prompt,
    messages = M.format_messages_for_claude(messages),
    tools = tools_module.to_claude_format(),
  }

  local json_body = vim.json.encode(body)

  -- Estimate prompt tokens
  local prompt_estimate = logs.estimate_tokens(json_body)
  logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))
  logs.thinking("Sending to Claude API...")

  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    API_URL,
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. api_key,
    "-H", "anthropic-version: 2023-06-01",
    "-d", json_body,
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
          logs.error("Failed to parse Claude response")
          callback(nil, "Failed to parse Claude response")
        end)
        return
      end

      if response.error then
        vim.schedule(function()
          logs.error(response.error.message or "Claude API error")
          callback(nil, response.error.message or "Claude API error")
        end)
        return
      end

      -- Log token usage from response
      if response.usage then
        logs.response(
          response.usage.input_tokens or 0,
          response.usage.output_tokens or 0,
          response.stop_reason
        )
      end

      -- Log what's in the response
      if response.content then
        for _, block in ipairs(response.content) do
          if block.type == "text" then
            logs.thinking("Response contains text")
          elseif block.type == "tool_use" then
            logs.thinking("Tool call: " .. block.name)
          end
        end
      end

      -- Return raw response for parser to handle
      vim.schedule(function()
        callback(response, nil)
      end)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        vim.schedule(function()
          logs.error("Claude API request failed: " .. table.concat(data, "\n"))
          callback(nil, "Claude API request failed: " .. table.concat(data, "\n"))
        end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          logs.error("Claude API request failed with code: " .. code)
          callback(nil, "Claude API request failed with code: " .. code)
        end)
      end
    end,
  })
end

--- Format messages for Claude API
---@param messages table[] Internal message format
---@return table[] Claude API message format
function M.format_messages_for_claude(messages)
  local formatted = {}

  for _, msg in ipairs(messages) do
    if msg.role == "user" then
      if type(msg.content) == "table" then
        -- Tool results
        table.insert(formatted, {
          role = "user",
          content = msg.content,
        })
      else
        table.insert(formatted, {
          role = "user",
          content = msg.content,
        })
      end
    elseif msg.role == "assistant" then
      -- Build content array for assistant messages
      local content = {}

      -- Add text if present
      if msg.content and msg.content ~= "" then
        table.insert(content, {
          type = "text",
          text = msg.content,
        })
      end

      -- Add tool uses if present
      if msg.tool_calls then
        for _, tool_call in ipairs(msg.tool_calls) do
          table.insert(content, {
            type = "tool_use",
            id = tool_call.id,
            name = tool_call.name,
            input = tool_call.parameters,
          })
        end
      end

      if #content > 0 then
        table.insert(formatted, {
          role = "assistant",
          content = content,
        })
      end
    end
  end

  return formatted
end

return M
