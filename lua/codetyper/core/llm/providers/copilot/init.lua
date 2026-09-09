--- Copilot provider — wires auth, request, response
local M = {}

local auth = require("codetyper.core.llm.providers.copilot.auth")
local request = require("codetyper.core.llm.providers.copilot.request")
local parse_response = require("codetyper.core.llm.providers.copilot.response")
local utils = require("codetyper.support.utils")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Get model from stored credentials or config
---@param context table|nil Request context (used to pick ask_model for question calls)
---@return string Model name
local function get_model(context)
  -- For ask/explain calls, use the cheaper ask_model when configured
  if context and context.prompt_type == "ask" then
    local ok_ct, codetyper = pcall(require, "codetyper")
    if ok_ct then
      local config = codetyper.get_config()
      if config and config.llm and config.llm.copilot and config.llm.copilot.ask_model then
        return config.llm.copilot.ask_model
      end
    end
  end

  local ok_cred, credentials = pcall(require, "codetyper.config.credentials")
  if ok_cred then
    local stored = credentials.get_model("copilot")
    if stored then
      return stored
    end
  end

  local ok_ct, codetyper = pcall(require, "codetyper")
  if ok_ct then
    local config = codetyper.get_config()
    if config and config.llm and config.llm.copilot then
      return config.llm.copilot.model
    end
  end

  return "claude-sonnet-4"
end

local function native_tools_enabled(context, model)
  if not context or context.is_project_task ~= true then
    return false, "native tools require a Copilot project task"
  end
  if context.provider and context.provider ~= "copilot" then
    return false, "native tools are unavailable for this provider"
  end
  local model_caps = require("codetyper.constants.model_caps")
  local caps = model_caps.get(model)
  if not caps or caps.tools ~= true then
    return false, "the selected Copilot model does not advertise native tools"
  end
  return true, nil
end

local function native_registry_tool(definition)
  if type(definition) ~= "table" or definition.available ~= true or definition.stale == true then
    return nil
  end
  local parameters = definition.parameters or definition.inputSchema or definition.schema
  if type(definition.name) ~= "string" or type(parameters) ~= "table" then
    return nil
  end
  return {
    type = "function",
    ["function"] = {
      name = definition.name,
      description = definition.description or "Bounded project agent tool",
      parameters = parameters,
    },
  }
end

--- Return the explicit Copilot native/marker capability decision.
---@param context table|nil Request context
---@return table { provider, native_tools, marker_tools, reason, tools }
function M.get_tool_capabilities(context)
  local model = get_model(context)
  local enabled, reason = native_tools_enabled(context, model)
  local tools = {}
  if enabled then
    local registry = require("codetyper.core.agent.tools")
    local definitions = registry.list(context and context.tool_options or nil)
    for _, definition in ipairs(definitions or {}) do
      local tool = native_registry_tool(definition)
      if tool then
        tools[#tools + 1] = tool
      end
    end

    tools[#tools + 1] = request.terminal_tool
    local mcp = require("codetyper.core.agent.mcp")
    for _, tool in ipairs(mcp.get_tools_for_api() or {}) do
      tools[#tools + 1] = tool
    end
  end
  return {
    provider = "copilot",
    native_tools = enabled,
    marker_tools = true,
    reason = reason,
    tools = tools,
  }
end

M.tool_capabilities = M.get_tool_capabilities

--- Track if we've already suggested Ollama fallback this session
local ollama_fallback_suggested = false

--- Suggest switching to Ollama when rate limits are hit
---@param error_msg string
local function suggest_ollama_fallback(error_msg)
  if ollama_fallback_suggested then
    return
  end

  vim.fn.jobstart({ "curl", "-s", "http://localhost:11434/api/tags" }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          local ok_ct, codetyper = pcall(require, "codetyper")
          if ok_ct then
            local config = codetyper.get_config()
            config.llm.provider = "ollama"
          end
          ollama_fallback_suggested = true
          utils.notify(
            "Copilot rate limit reached. Switched to Ollama.\n" .. error_msg:sub(1, 100),
            vim.log.levels.WARN
          )
        else
          utils.notify(
            "Copilot rate limit reached. Ollama not available.\nStart Ollama with: ollama serve",
            vim.log.levels.WARN
          )
        end
      end)
    end,
  })
end

--- Generate code using Copilot API
---@param prompt string User prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil)
function M.generate(prompt, context, callback)
  flog.info("copilot", string.format(">>> generate: model=%s prompt_len=%d", get_model(context), #(prompt or ""))) -- TODO: remove after debugging

  auth.get_valid_token(function(token, err)
    if err then
      local safe_err = auth.safe_error(err)
      utils.notify(safe_err, vim.log.levels.ERROR)
      callback(nil, safe_err)
      return
    end

    local valid, validation_error = auth.validate_exchange(token)
    if not valid then
      local safe_err = auth.safe_error(validation_error)
      utils.notify(safe_err, vim.log.levels.ERROR)
      callback(nil, safe_err)
      return
    end

    local system_prompt = ""
    if context and context.system_prompt then
      system_prompt = context.system_prompt
    else
      local build_sys = require("codetyper.core.llm.shared.build_system_prompt")
      system_prompt = build_sys(context or {})
    end

    local model = get_model(context)
    local body = request.build_body(model, system_prompt, prompt)
    utils.notify("Sending request to Copilot...", vim.log.levels.INFO)

    request.send(token, body, function(parsed, http_err)
      if http_err then
        local safe_err = auth.safe_error(http_err)
        if safe_err:match("limit") or safe_err:match("Upgrade") or safe_err:match("quota") then
          suggest_ollama_fallback(safe_err)
        end
        utils.notify(safe_err, vim.log.levels.ERROR)
        callback(nil, safe_err)
        return
      end

      local result = parse_response(parsed)

      -- Record usage
      if result.usage then
        pcall(function()
          local record_usage = require("codetyper.handler.record_usage")
          record_usage(
            model,
            result.usage.prompt_tokens or 0,
            result.usage.completion_tokens or 0,
            result.usage.cached_tokens or 0
          )
        end)
      end

      if result.error then
        local safe_err = auth.safe_error(result.error)
        if result.rate_limited then
          suggest_ollama_fallback(safe_err)
        end
        utils.notify(safe_err, vim.log.levels.ERROR)
        callback(nil, safe_err)
      else
        utils.notify("Code generated successfully", vim.log.levels.INFO)
        callback(result.code, nil, result.usage)
      end
    end)
  end)
end

--- Generate using streaming with native tool calling support
--- Returns structured result instead of a plain string.
---@param prompt string User prompt
---@param context table Context { system_prompt, messages, is_follow_up, prompt_type }
---@param callbacks table { on_text_delta: fun(str), on_complete: fun(result), on_error: fun(err) }
function M.generate_structured(prompt, context, callbacks)
  local model = get_model(context)
  flog.info("copilot", string.format(">>> generate_structured: model=%s prompt_len=%d", model, #(prompt or "")))

  auth.get_valid_token(function(token, err)
    if err then
      callbacks.on_error(auth.safe_error(err))
      return
    end

    local valid, validation_error = auth.validate_exchange(token)
    if not valid then
      callbacks.on_error(auth.safe_error(validation_error))
      return
    end

    -- Build system prompt
    local system_prompt = ""
    if context and context.system_prompt then
      system_prompt = context.system_prompt
    else
      local build_sys = require("codetyper.core.llm.shared.build_system_prompt")
      system_prompt = build_sys(context or {})
    end

    -- Native schemas are a Copilot-only project-task capability. Non-project
    -- requests and models without an explicit tools capability send no tools;
    -- they retain the validated text-marker contract instead.
    local tool_capabilities = M.get_tool_capabilities(context)
    local tools = tool_capabilities.tools

    -- Build body with streaming enabled
    local body = request.build_body(model, system_prompt, prompt, {
      messages = context and context.messages or nil,
      tools = #tools > 0 and tools or nil,
      stream = true,
      max_tokens = 16384,
    })

    -- Create stream accumulator
    local stream = require("codetyper.core.llm.providers.copilot.stream")
    local acc = stream.new()

    local job_id = request.send_stream(token, body, {
      is_follow_up = context and context.is_follow_up,
      on_chunk = function(json_str)
        local ok, chunk = pcall(vim.json.decode, json_str)
        if not ok then
          flog.debug("copilot.stream", "failed to decode chunk: " .. json_str:sub(1, 100))
          return
        end
        local delta = stream.process_chunk(acc, chunk)
        if delta.text_delta and callbacks.on_text_delta then
          callbacks.on_text_delta(delta.text_delta)
        end
      end,
      on_done = function()
        local result = stream.get_result(acc)
        flog.info(
          "copilot.stream",
          string.format(
            "complete: text_len=%d tool_calls=%d finish=%s",
            #result.text,
            #result.tool_calls,
            result.finish_reason or "nil"
          )
        )

        -- Record usage
        if result.usage then
          pcall(function()
            local record_usage = require("codetyper.handler.record_usage")
            record_usage(
              model,
              result.usage.prompt_tokens or 0,
              result.usage.completion_tokens or 0,
              (result.usage.prompt_tokens_details and result.usage.prompt_tokens_details.cached_tokens) or 0
            )
          end)
        end

        callbacks.on_complete(result)
      end,
      on_error = function(stream_err)
        local safe_stream_error = auth.safe_error(stream_err)
        flog.info("copilot.stream", "stream error, falling back to non-streaming: " .. safe_stream_error)
        -- Fallback: rebuild request as non-streaming but preserve conversation history
        local fallback_body = request.build_body(model, system_prompt, prompt, {
          messages = context and context.messages or nil,
          tools = #tools > 0 and tools or nil,
          stream = false,
          max_tokens = 16384,
        })
        request.send(token, fallback_body, function(parsed, http_err)
          if http_err then
            callbacks.on_error(auth.safe_error(http_err))
            return
          end
          local fb_result = parse_response(parsed)
          if fb_result.error then
            callbacks.on_error(auth.safe_error(fb_result.error))
            return
          end
          callbacks.on_complete({
            text = fb_result.code or "",
            tool_calls = {},
            usage = fb_result.usage,
            finish_reason = "stop",
          })
        end)
      end,
    })

    -- Store job_id on context for cancellation
    if context then
      context._stream_job_id = job_id
    end
  end)
end

--- Validate configuration
---@return boolean, string|nil
function M.validate()
  return auth.is_authenticated(), auth.is_authenticated() and nil or "Copilot not authenticated"
end

--- Expose state for backwards compatibility
M.state = auth.state

return M
