--- Ollama request building and sending
local M = {}

local http = require("codetyper.core.llm.shared.http")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Build request body for Ollama API
---@param model string Model name
---@param system_prompt string System prompt
---@param user_prompt string User prompt
---@return table Request body
function M.build_body(model, system_prompt, user_prompt)
  return {
    model = model,
    system = system_prompt,
    prompt = user_prompt,
    stream = false,
    options = {
      temperature = 0.2,
      num_predict = 4096,
    },
  }
end

--- Send request to Ollama API
---@param host string Ollama host URL
---@param body table Request body
---@param callback fun(parsed: table|nil, error: string|nil)
function M.send(host, body, callback)
  local url = host .. "/api/generate"
  local json_body = vim.json.encode(body)
  local headers = { "Content-Type: application/json" }

  flog.info("ollama.request", "POST " .. url .. " model=" .. (body.model or "nil")) -- TODO: remove after debugging

  http.post(url, headers, json_body, callback)
end

return M
