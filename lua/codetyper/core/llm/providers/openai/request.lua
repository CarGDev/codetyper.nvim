--- Non-streaming ChatGPT Codex Responses request adapter.
local auth = require("codetyper.core.llm.providers.openai.auth")
local oauth = require("codetyper.core.llm.providers.openai.oauth")
local http = require("codetyper.core.llm.shared.http")

local M = {}

local ENDPOINT = oauth.CODEX_API_ENDPOINT

local function has_text(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function safe_error(value)
  return auth.redact and auth.redact(value) or oauth.redact(value)
end

local function unsupported_options(options)
  options = options or {}
  if options.stream == true then
    return "OpenAI ChatGPT streaming is not supported"
  end
  if options.tools ~= nil then
    return "OpenAI ChatGPT tools are not supported"
  end
  return nil
end

--- Build the limited request body supported by the ChatGPT subscription slice.
---@param model string
---@param system_prompt string|nil
---@param user_prompt string|nil
---@param options table|nil
---@return table|nil body, string|nil error
function M.build_body(model, system_prompt, user_prompt, options)
  options = options or {}
  local option_error = unsupported_options(options)
  if option_error then
    return nil, option_error
  end
  if not has_text(model) then
    return nil, "OpenAI ChatGPT model is required"
  end
  return {
    model = model,
    instructions = system_prompt or "",
    input = user_prompt or "",
    stream = false,
  },
    nil
end

--- Build verified request headers without exposing credentials to callers.
---@param token table
---@return string[] headers, string|nil error
function M.build_headers(token)
  local access_token = token and (token.access_token or token.access)
  if not has_text(access_token) then
    return nil, "OpenAI authentication is unavailable"
  end
  if not has_text(token.account_id) then
    return nil, "OpenAI ChatGPT account identity is unavailable"
  end
  local headers = {
    "Authorization: Bearer " .. access_token,
    "Content-Type: application/json",
    "ChatGPT-Account-Id: " .. token.account_id,
  }
  if has_text(token.residency) then
    headers[#headers + 1] = "x-openai-internal-codex-residency: " .. token.residency
  end
  return headers, nil
end

--- Send a non-streaming request. Cancellation suppresses all late callbacks.
---@param body table
---@param callback fun(parsed: table|nil, error: string|nil, metadata: table|nil)
---@return table handle
function M.send(body, callback)
  callback = callback or function() end
  local cancelled, finished = false, false
  local auth_handle, request_handle
  local handle = {}

  local function finish(parsed, err, metadata)
    if finished or cancelled then
      return
    end
    finished = true
    callback(parsed, err and safe_error(err) or nil, metadata)
  end

  function handle.cancel()
    if finished or cancelled then
      return
    end
    cancelled, finished = true, true
    if auth_handle and auth_handle.cancel then
      auth_handle.cancel()
    end
    if request_handle and request_handle.cancel then
      request_handle.cancel()
    end
  end

  if type(body) ~= "table" then
    finish(nil, "OpenAI request body is required")
    return handle
  end
  if body.stream == true then
    finish(nil, "OpenAI ChatGPT streaming is not supported")
    return handle
  end
  if body.tools ~= nil then
    finish(nil, "OpenAI ChatGPT tools are not supported")
    return handle
  end

  local ok, encoded = pcall(vim.json.encode, body)
  if not ok then
    finish(nil, "OpenAI request body could not be encoded")
    return handle
  end

  auth_handle = auth.get_valid(function(token, auth_error)
    if cancelled or finished then
      return
    end
    if auth_error then
      finish(nil, auth_error)
      return
    end
    local headers, header_error = M.build_headers(token)
    if not headers then
      finish(nil, header_error)
      return
    end
    request_handle = http.post(ENDPOINT, headers, encoded, function(parsed, err, metadata)
      if err then
        finish(nil, err, metadata)
      else
        finish(parsed, nil, metadata)
      end
    end)
  end)
  return handle
end

M.endpoint = ENDPOINT
M.unsupported_options = unsupported_options

return M
