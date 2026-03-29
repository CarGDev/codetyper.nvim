--- Ollama provider — wires config, request, response
local M = {}

local ollama_config = require("codetyper.core.llm.providers.ollama.config")
local request = require("codetyper.core.llm.providers.ollama.request")
local parse_response = require("codetyper.core.llm.providers.ollama.response")
local utils = require("codetyper.support.utils")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Generate code using Ollama API
---@param prompt string User prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil, usage: table|nil)
function M.generate(prompt, context, callback)
  local host = ollama_config.get_host()
  local model = ollama_config.get_model()

  flog.info("ollama", string.format(">>> generate: model=%s prompt_len=%d", model, #(prompt or ""))) -- TODO: remove after debugging

  local system_prompt = ""
  if context and context.system_prompt then
    system_prompt = context.system_prompt
  else
    local build_sys = require("codetyper.core.llm.shared.build_system_prompt")
    system_prompt = build_sys(context or {})
  end

  local body = request.build_body(model, system_prompt, prompt)
  utils.notify("Sending request to Ollama...", vim.log.levels.INFO)

  request.send(host, body, function(parsed, err)
    if err then
      utils.notify(err, vim.log.levels.ERROR)
      callback(nil, err)
      return
    end

    local result = parse_response(parsed)

    if result.error then
      utils.notify(result.error, vim.log.levels.ERROR)
      callback(nil, result.error)
    else
      utils.notify("Code generated successfully", vim.log.levels.INFO)
      callback(result.code, nil, result.usage)
    end
  end)
end

--- Check if Ollama is reachable
---@param callback fun(ok: boolean, error: string|nil)
function M.health_check(callback)
  local host = ollama_config.get_host()
  local http_mod = require("codetyper.core.llm.shared.http")

  http_mod.get(host .. "/api/tags", {}, function(_, err)
    if err then
      callback(false, "Cannot connect to Ollama at " .. host)
    else
      callback(true, nil)
    end
  end)
end

--- Validate configuration
---@return boolean, string|nil
function M.validate()
  local host = ollama_config.get_host()
  if not host or host == "" then
    return false, "Ollama host not configured"
  end
  local model = ollama_config.get_model()
  if not model or model == "" then
    return false, "Ollama model not configured"
  end
  return true
end

return M
