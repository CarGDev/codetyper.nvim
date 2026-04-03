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
      utils.notify(err, vim.log.levels.ERROR)
      callback(nil, err)
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
        if http_err:match("limit") or http_err:match("Upgrade") or http_err:match("quota") then
          suggest_ollama_fallback(http_err)
        end
        utils.notify(http_err, vim.log.levels.ERROR)
        callback(nil, http_err)
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
        if result.rate_limited then
          suggest_ollama_fallback(result.error)
        end
        utils.notify(result.error, vim.log.levels.ERROR)
        callback(nil, result.error)
      else
        utils.notify("Code generated successfully", vim.log.levels.INFO)
        callback(result.code, nil, result.usage)
      end
    end)
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
