--- Copilot request building and sending
local M = {}

local http = require("codetyper.core.llm.shared.http")
local flog = require("codetyper.support.flog")

--- Terminal tool definition in OpenAI function-calling format
M.terminal_tool = {
  type = "function",
  ["function"] = {
    name = "terminal",
    description = "Run a shell command in the project directory and return its stdout/stderr output. "
      .. "Use for: listing files, reading file contents, checking dependencies, running tests, "
      .. "grep/search, checking git status.",
    parameters = {
      type = "object",
      properties = {
        command = {
          type = "string",
          description = "The shell command to execute",
        },
      },
      required = { "command" },
    },
  },
}

--- Build request headers for Copilot API
---@param token table GitHub token with .token field
---@param opts table|nil { is_follow_up: boolean }
---@return string[] Headers
function M.build_headers(token, opts)
  opts = opts or {}
  local headers = {
    "Authorization: Bearer " .. token.token,
    "Content-Type: application/json",
    "User-Agent: GitHubCopilotChat/0.32.4",
    "Editor-Version: vscode/1.105.1",
    "Editor-Plugin-Version: copilot-chat/0.32.4",
    "Copilot-Integration-Id: vscode-chat",
    "Openai-Intent: conversation-edits",
  }
  -- X-Initiator: agent for follow-up turns in tool-calling loops
  if opts.is_follow_up then
    table.insert(headers, "X-Initiator: agent")
  else
    table.insert(headers, "X-Initiator: user")
  end
  return headers
end

--- Build request body for Copilot API
---@param model string Model name
---@param system_prompt string System prompt
---@param user_prompt string User prompt
---@param opts table|nil { messages: table[], tools: table[], stream: boolean, max_tokens: number }
---@return table Request body
function M.build_body(model, system_prompt, user_prompt, opts)
  opts = opts or {}
  local body = {
    model = model,
    messages = opts.messages or {
      { role = "system", content = system_prompt },
      { role = "user", content = user_prompt },
    },
    max_tokens = opts.max_tokens or 16384,
    temperature = 0.2,
  }

  -- Explicit stream control: default false for backward compat with generate()
  if opts.stream ~= nil then
    body.stream = opts.stream
  else
    body.stream = false
  end

  -- Native tool calling
  if opts.tools and #opts.tools > 0 then
    body.tools = opts.tools
    body.tool_choice = "auto"
  end

  return body
end

--- Send non-streaming request to Copilot API
---@param token table GitHub token
---@param body table Request body
---@param callback fun(parsed: table|nil, error: string|nil)
function M.send(token, body, callback)
  local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com")
    .. "/chat/completions"
  local json_body = vim.json.encode(body)
  local headers = M.build_headers(token)

  flog.info("copilot.request", "POST " .. endpoint .. " body_len=" .. #json_body)

  http.post(endpoint, headers, json_body, callback)
end

--- Send streaming request to Copilot API
---@param token table GitHub token
---@param body table Request body (must have stream=true)
---@param opts table { on_chunk: fun(json_str), on_done: fun(), on_error: fun(err), is_follow_up: boolean|nil }
---@return number job_id for cancellation
function M.send_stream(token, body, opts)
  local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com")
    .. "/chat/completions"
  local json_body = vim.json.encode(body)
  local headers = M.build_headers(token, { is_follow_up = opts.is_follow_up })

  flog.info("copilot.request", "POST_STREAM " .. endpoint .. " model=" .. (body.model or "?")
    .. " body_len=" .. #json_body
    .. " tools=" .. (body.tools and #body.tools or 0))

  return http.post_stream(endpoint, headers, json_body, {
    on_chunk = opts.on_chunk,
    on_done = opts.on_done,
    on_error = opts.on_error,
  })
end

return M
