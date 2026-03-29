--- Ollama response parsing — pure function
local extract_code = require("codetyper.core.llm.shared.extract_code")

--- Parse Ollama API response
---@param parsed table JSON-decoded response
---@return table { code: string|nil, error: string|nil, usage: table|nil }
local function parse(parsed)
  if not parsed then
    return { code = nil, error = "Empty response", usage = nil }
  end

  if parsed.error then
    return { code = nil, error = parsed.error or "Ollama API error", usage = nil }
  end

  local usage = {
    prompt_tokens = parsed.prompt_eval_count or 0,
    response_tokens = parsed.eval_count or 0,
  }

  if parsed.response then
    local code = extract_code(parsed.response)
    return { code = code, error = nil, usage = usage }
  end

  return { code = nil, error = "No response from Ollama", usage = nil }
end

return parse
