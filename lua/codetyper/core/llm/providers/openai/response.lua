--- Pure parser for the provider-specific non-streaming Responses payload.
local extract_code = require("codetyper.core.llm.shared.extract_code")
local oauth = require("codetyper.core.llm.providers.openai.oauth")

local M = {}

local function error_message(value)
  if type(value) == "string" and value ~= "" then
    return oauth.redact(value)
  end
  if type(value) == "table" then
    if type(value.message) == "string" and value.message ~= "" then
      return oauth.redact(value.message)
    end
    if type(value.code) == "string" and value.code ~= "" then
      return oauth.redact(value.code)
    end
  end
  return "OpenAI Codex API error"
end

local function collect_text(output)
  local parts = {}
  for _, item in ipairs(type(output) == "table" and output or {}) do
    if type(item) == "table" then
      if type(item.text) == "string" then
        parts[#parts + 1] = item.text
      end
      for _, content in ipairs(type(item.content) == "table" and item.content or {}) do
        if type(content) == "table" and type(content.text) == "string" then
          parts[#parts + 1] = content.text
        end
      end
    end
  end
  return table.concat(parts, "")
end

--- Parse a Codex Responses response into Codetyper's common contract.
---@param parsed table|nil
---@return table { code: string|nil, text: string|nil, error: string|nil, usage: table|nil }
function M.parse(parsed)
  if type(parsed) ~= "table" then
    return { code = nil, text = nil, error = "Empty OpenAI response", usage = nil }
  end
  if parsed.type == "error" or parsed.error then
    return { code = nil, text = nil, error = error_message(parsed.error), usage = nil }
  end

  local text = type(parsed.output_text) == "string" and parsed.output_text or collect_text(parsed.output)
  if text == "" then
    return { code = nil, text = nil, error = "OpenAI response contained no text", usage = nil }
  end

  local raw_usage = type(parsed.usage) == "table" and parsed.usage or {}
  return {
    code = extract_code(text),
    text = text,
    error = nil,
    usage = {
      prompt_tokens = raw_usage.input_tokens or raw_usage.prompt_tokens or 0,
      completion_tokens = raw_usage.output_tokens or raw_usage.completion_tokens or 0,
      cached_tokens = raw_usage.cached_tokens or 0,
    },
  }
end

return M
