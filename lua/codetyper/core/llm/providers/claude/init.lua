--- Anthropic provider — discovery and non-streaming generation.
local models = require("codetyper.core.llm.providers.claude.models")
local request = require("codetyper.core.llm.providers.claude.request")
local parse_response = require("codetyper.core.llm.providers.claude.response")
local flog = require("codetyper.support.flog")
local utils = require("codetyper.support.utils")

local M = {}

local function get_model(context)
  context = context or {}
  return context.model or context.model_id or "claude-sonnet-4-5"
end

local function get_system_prompt(context)
  if context and context.system_prompt then
    return context.system_prompt
  end
  local build_system_prompt = require("codetyper.core.llm.shared.build_system_prompt")
  return build_system_prompt(context or {})
end

local function redact_diagnostic(value)
  local message = tostring(value or "")
  local key = models.get_api_key()
  if type(key) == "string" and key ~= "" then
    local escaped_key = key:gsub("([^%w])", "%%%1")
    message = message:gsub(escaped_key, "[REDACTED]")
  end
  return message
end

local function report_error(message)
  local safe_message = redact_diagnostic(message)
  flog.error("claude", safe_message)
  utils.notify(safe_message, vim.log.levels.ERROR)
  return safe_message
end

--- Generate content through Anthropic's non-streaming messages API.
---@param prompt string
---@param context table|nil
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil)
function M.generate(prompt, context, callback)
  callback = callback or function() end
  if not models.is_available() then
    local err = "Anthropic unavailable: ANTHROPIC_API_KEY is not set"
    local safe_err = report_error(err)
    callback(nil, safe_err)
    return
  end

  local body, body_error = request.build_body(get_model(context), get_system_prompt(context), prompt, context)
  if body_error then
    local safe_err = report_error(body_error)
    callback(nil, safe_err)
    return
  end

  utils.notify("Sending request to Anthropic...", vim.log.levels.INFO)
  request.send(body, function(parsed, err)
    if err then
      local safe_err = report_error(err)
      callback(nil, safe_err)
      return
    end

    local result = parse_response.parse(parsed)
    if result.error then
      local safe_err = report_error(result.error)
      callback(nil, safe_err)
      return
    end

    utils.notify("Code generated successfully", vim.log.levels.INFO)
    callback(result.code, nil, result.usage)
  end)
end

function M.validate()
  return models.is_available(), models.is_available() and nil or "Anthropic not configured"
end

M.models = models
M.request = request
M.response = parse_response
M.get_model = get_model

return M
