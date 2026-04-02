--- Ollama host and model resolution from credentials + config
local M = {}

--- Get Ollama host URL
---@return string Host URL
function M.get_host()
  local ok_cred, credentials = pcall(require, "codetyper.config.credentials")
  if ok_cred then
    local stored_host = credentials.get_ollama_host()
    if stored_host then
      return stored_host
    end
  end

  local ok_ct, codetyper = pcall(require, "codetyper")
  if ok_ct then
    local config = codetyper.get_config()
    if config and config.llm and config.llm.ollama then
      return config.llm.ollama.host
    end
  end

  return "http://localhost:11434"
end

--- Get Ollama model name
---@param context table|nil Request context (used to pick ask_model for question calls)
---@return string Model name
function M.get_model(context)
  -- For ask/explain calls, use the cheaper ask_model when configured
  if context and context.prompt_type == "ask" then
    local ok_ct, codetyper = pcall(require, "codetyper")
    if ok_ct then
      local config = codetyper.get_config()
      if config and config.llm and config.llm.ollama and config.llm.ollama.ask_model then
        return config.llm.ollama.ask_model
      end
    end
  end

  local ok_cred, credentials = pcall(require, "codetyper.config.credentials")
  if ok_cred then
    local stored_model = credentials.get_model("ollama")
    if stored_model then
      return stored_model
    end
  end

  local ok_ct, codetyper = pcall(require, "codetyper")
  if ok_ct then
    local config = codetyper.get_config()
    if config and config.llm and config.llm.ollama then
      return config.llm.ollama.model
    end
  end

  return "llama3"
end

return M
