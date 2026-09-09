--- OpenAI ChatGPT Plus/Pro provider facade.
local auth = require("codetyper.core.llm.providers.openai.auth")
local models = require("codetyper.core.llm.providers.openai.models")
local request = require("codetyper.core.llm.providers.openai.request")
local response = require("codetyper.core.llm.providers.openai.response")

local M = {}

local function get_model(context)
  context = context or {}
  if context.model or context.model_id then
    return context.model or context.model_id
  end
  local ok, credentials = pcall(require, "codetyper.config.credentials")
  if ok and credentials.get_model then
    local stored = credentials.get_model("openai")
    if stored then
      return stored
    end
  end
  return "gpt-5.5"
end

local function get_system_prompt(context)
  if context and context.system_prompt then
    return context.system_prompt
  end
  local build_system_prompt = require("codetyper.core.llm.shared.build_system_prompt")
  return build_system_prompt(context or {})
end

local function notify(message, level)
  pcall(vim.notify, message, level)
end

--- Generate non-streaming text through the ChatGPT Codex endpoint.
---@param prompt string
---@param context table|nil
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil)
---@return table handle
function M.generate(prompt, context, callback)
  callback = callback or function() end
  local body, body_error = request.build_body(get_model(context), get_system_prompt(context), prompt, context)
  if body_error then
    callback(nil, body_error)
    return { cancel = function() end }
  end
  notify("Sending request to OpenAI (ChatGPT Plus/Pro)...", vim.log.levels.INFO)
  return request.send(body, function(parsed, err)
    if err then
      notify(err, vim.log.levels.ERROR)
      callback(nil, err)
      return
    end
    local result = response.parse(parsed)
    if result.error then
      notify(result.error, vim.log.levels.ERROR)
      callback(nil, result.error)
      return
    end
    notify("Code generated successfully", vim.log.levels.INFO)
    local metadata = vim.deepcopy(result.usage or {})
    metadata.provider = models.PROVIDER
    metadata.subscription = true
    metadata.catalog_version = models.ALLOWLIST_VERSION
    callback(result.code, nil, metadata)
  end)
end

---@return boolean, string|nil
function M.validate()
  local valid = auth.is_authenticated()
  return valid, valid and nil or "OpenAI ChatGPT subscription is not authenticated"
end

M.auth = auth
M.models = models
M.request = request
M.response = response
M.get_model = get_model

return M
