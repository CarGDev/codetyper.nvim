--- Copilot request building and sending
local M = {}

local http = require("codetyper.core.llm.shared.http")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Build request headers for Copilot API
---@param token table GitHub token with .token field
---@return string[] Headers
function M.build_headers(token)
  return {
    "Authorization: Bearer " .. token.token,
    "Content-Type: application/json",
    "User-Agent: GitHubCopilotChat/0.26.7",
    "Editor-Version: vscode/1.105.1",
    "Editor-Plugin-Version: copilot-chat/0.26.7",
    "Copilot-Integration-Id: vscode-chat",
    "Openai-Intent: conversation-edits",
  }
end

--- Build request body for Copilot API
---@param model string Model name
---@param system_prompt string System prompt
---@param user_prompt string User prompt
---@return table Request body
function M.build_body(model, system_prompt, user_prompt)
  return {
    model = model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = user_prompt },
    },
    max_tokens = 4096,
    temperature = 0.2,
    stream = false,
  }
end

--- Send request to Copilot API
---@param token table GitHub token
---@param body table Request body
---@param callback fun(parsed: table|nil, error: string|nil)
function M.send(token, body, callback)
  local endpoint = (token.endpoints and token.endpoints.api or "https://api.githubcopilot.com")
    .. "/chat/completions"
  local json_body = vim.json.encode(body)
  local headers = M.build_headers(token)

  flog.info("copilot.request", "POST " .. endpoint .. " body_len=" .. #json_body) -- TODO: remove after debugging

  http.post(endpoint, headers, json_body, callback)
end

return M
