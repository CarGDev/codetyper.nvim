--- Non-streaming Anthropic messages request adapter.
local http = require("codetyper.core.llm.shared.http")
local models = require("codetyper.core.llm.providers.claude.models")

local M = {}

local API_VERSION = "2023-06-01"
local API_BASE = "https://api.anthropic.com"

local function unsupported_options(options)
  options = options or {}
  if options.stream == true then
    return "Claude streaming is not supported"
  end
  if options.tools ~= nil then
    return "Claude tools are not supported"
  end
  return nil
end

--- Build a non-streaming Anthropic messages body.
---@param model string
---@param system_prompt string|nil
---@param user_prompt string|nil
---@param options table|nil { messages: table[], max_tokens: number, stream: boolean, tools: table }
---@return table|nil body, string|nil error
function M.build_body(model, system_prompt, user_prompt, options)
  options = options or {}
  local option_error = unsupported_options(options)
  if option_error then
    return nil, option_error
  end
  if type(model) ~= "string" or model == "" then
    return nil, "Claude model is required"
  end

  local messages = options.messages
  if type(messages) ~= "table" or #messages == 0 then
    messages = { { role = "user", content = user_prompt or "" } }
  end

  return {
    model = model,
    max_tokens = options.max_tokens or 4096,
    system = system_prompt or "",
    messages = messages,
    stream = false,
  }
end

local function headers(key)
  return {
    "x-api-key: " .. key,
    "anthropic-version: " .. API_VERSION,
    "content-type: application/json",
  }
end

--- Send a non-streaming Anthropic messages request.
---@param body table
---@param callback fun(parsed: table|nil, error: string|nil, metadata: table|nil)
---@param options table|nil { base_url: string }
---@return table|nil handle
function M.send(body, callback, options)
  callback = callback or function() end
  options = options or {}
  local key = models.get_api_key()
  if not key then
    callback(nil, "Anthropic unavailable: ANTHROPIC_API_KEY is not set")
    return nil
  end
  if type(body) ~= "table" then
    callback(nil, "Claude request body is required")
    return nil
  end
  if body.stream == true then
    callback(nil, "Claude streaming is not supported")
    return nil
  end
  if body.tools ~= nil then
    callback(nil, "Claude tools are not supported")
    return nil
  end

  local ok, encoded = pcall(vim.json.encode, body)
  if not ok then
    callback(nil, "Failed to encode Claude request")
    return nil
  end

  local base_url = (options.base_url or API_BASE):gsub("/+$", "")
  return http.post(base_url .. "/v1/messages", headers(key), encoded, callback)
end

M.headers = headers
M.api_version = API_VERSION
M.base_url = API_BASE

return M
