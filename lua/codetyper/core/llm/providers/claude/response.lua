--- Pure Anthropic messages response parser.
local extract_code = require("codetyper.core.llm.shared.extract_code")

local M = {}

local function error_message(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
  if type(value) == "table" and type(value.message) == "string" and value.message ~= "" then
    return value.message
  end
  return "Anthropic API error"
end

--- Parse an Anthropic response into Codetyper's common generation contract.
---@param parsed table|nil
---@return table { code: string|nil, error: string|nil, usage: table|nil }
function M.parse(parsed)
  if type(parsed) ~= "table" then
    return { code = nil, error = "Empty response", usage = nil }
  end

  if parsed.type == "error" or parsed.error or parsed.message then
    return { code = nil, error = error_message(parsed.error or parsed.message), usage = nil }
  end

  local content = parsed.content
  if type(content) ~= "table" then
    return { code = nil, error = "No content in Anthropic response", usage = nil }
  end

  local text_parts = {}
  for _, block in ipairs(content) do
    if type(block) == "table" and block.type == "text" and type(block.text) == "string" then
      text_parts[#text_parts + 1] = block.text
    end
  end
  if #text_parts == 0 then
    return { code = nil, error = "No content in Anthropic response", usage = nil }
  end

  local raw_usage = type(parsed.usage) == "table" and parsed.usage or {}
  return {
    code = extract_code(table.concat(text_parts)),
    error = nil,
    usage = {
      prompt_tokens = raw_usage.input_tokens or 0,
      completion_tokens = raw_usage.output_tokens or 0,
    },
  }
end

return M
