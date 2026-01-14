---@mod codetyper.llm.ollama Ollama API client for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")
local llm = require("codetyper.llm")

--- Get Ollama host from config
---@return string Host URL
local function get_host()
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  return config.llm.ollama.host
end

--- Get model from config
---@return string Model name
local function get_model()
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
---@param callback fun(response: string|nil, error: string|nil) Callback function
local function make_request(body, callback)
  local host = get_host()
  local url = host .. "/api/generate"
  local json_body = vim.json.encode(body)

  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    url,
    "-H", "Content-Type: application/json",
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
          callback(nil, "Failed to parse Ollama response")
        end)
        return
      end

      if response.error then
        vim.schedule(function()
          callback(nil, response.error or "Ollama API error")
        end)
        return
      end

      if response.response then
        local code = llm.extract_code(response.response)
        vim.schedule(function()
          callback(code, nil)
        end)
      else
        vim.schedule(function()
          callback(nil, "No response from Ollama")
        end)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        vim.schedule(function()
          callback(nil, "Ollama API request failed: " .. table.concat(data, "\n"))
        end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          callback(nil, "Ollama API request failed with code: " .. code)
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
  utils.notify("Sending request to Ollama...", vim.log.levels.INFO)

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

--- Build system prompt for agent mode with tool instructions
---@param context table Context information
---@return string System prompt
local function build_agent_system_prompt(context)
  local agent_prompts = require("codetyper.prompts.agent")
  local tools_module = require("codetyper.agent.tools")

  local system_prompt = agent_prompts.system .. "\n\n"
  system_prompt = system_prompt .. tools_module.to_prompt_format() .. "\n\n"
  system_prompt = system_prompt .. agent_prompts.tool_instructions

  -- Add context about current file if available
  if context.file_path then
    system_prompt = system_prompt .. "\n\nCurrent working context:\n"
    system_prompt = system_prompt .. "- File: " .. context.file_path .. "\n"
    if context.language then
      system_prompt = system_prompt .. "- Language: " .. context.language .. "\n"
    end
  end

  -- Add project root info
  local root = utils.get_project_root()
  if root then
    system_prompt = system_prompt .. "- Project root: " .. root .. "\n"
  end

  return system_prompt
end

--- Build request body for Ollama API with tools (chat format)
---@param messages table[] Conversation messages
---@param context table Context information
---@return table Request body
local function build_tools_request_body(messages, context)
  local system_prompt = build_agent_system_prompt(context)

  -- Convert messages to Ollama chat format
  local ollama_messages = {}
  for _, msg in ipairs(messages) do
    local content = msg.content
    -- Handle complex content (like tool results)
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

    table.insert(ollama_messages, {
      role = msg.role,
      content = content,
    })
  end

  return {
    model = get_model(),
    messages = ollama_messages,
    system = system_prompt,
    stream = false,
    options = {
      temperature = 0.3,
      num_predict = 4096,
    },
  }
end

--- Make HTTP request to Ollama chat API
---@param body table Request body
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil) Callback function
local function make_chat_request(body, callback)
  local host = get_host()
  local url = host .. "/api/chat"
  local json_body = vim.json.encode(body)

  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    url,
    "-H", "Content-Type: application/json",
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

      -- Return the message content for agent parsing
      if response.message and response.message.content then
        vim.schedule(function()
          callback(response.message.content, nil, usage)
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
        -- Don't double-report errors
      end
    end,
  })
end

--- Generate response with tools using Ollama API
---@param messages table[] Conversation history
---@param context table Context information
---@param tools table Tool definitions (embedded in prompt for Ollama)
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate_with_tools(messages, context, tools, callback)
  local logs = require("codetyper.agent.logs")

  -- Log the request
  local model = get_model()
  logs.request("ollama", model)
  logs.thinking("Preparing API request...")

  local body = build_tools_request_body(messages, context)

  -- Estimate prompt tokens
  local prompt_estimate = logs.estimate_tokens(vim.json.encode(body))
  logs.debug(string.format("Estimated prompt: ~%d tokens", prompt_estimate))

  make_chat_request(body, function(response, err, usage)
    if err then
      logs.error(err)
      callback(nil, err)
    else
      -- Log token usage
      if usage then
        logs.response(
          usage.prompt_tokens or 0,
          usage.response_tokens or 0,
          "end_turn"
        )
      end

      -- Log if response contains tool calls
      if response then
        local parser = require("codetyper.agent.parser")
        local parsed = parser.parse_ollama_response(response)
        if #parsed.tool_calls > 0 then
          for _, tc in ipairs(parsed.tool_calls) do
            logs.thinking("Tool call: " .. tc.name)
          end
        end
        if parsed.text and parsed.text ~= "" then
          logs.thinking("Response contains text")
        end
      end

      callback(response, nil)
    end
  end)
end

return M
