--- Copilot response parsing — pure function, no side effects
local extract_code = require("codetyper.core.llm.shared.extract_code")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Parse Copilot API response
---@param parsed table JSON-decoded response
---@return table { code: string|nil, error: string|nil, usage: table|nil, rate_limited: boolean }
local function parse(parsed)
  if not parsed then
    return { code = nil, error = "Empty response", usage = nil, rate_limited = false }
  end

  -- Check for API error
  if parsed.error then
    local msg = parsed.error.message or tostring(parsed.error)
    local rate_limited = msg:match("limit") or msg:match("Upgrade") or msg:match("quota")
    return { code = nil, error = msg, usage = nil, rate_limited = rate_limited ~= nil }
  end

  -- Extract usage info
  local usage = parsed.usage or {}

  -- Extract code from response
  if parsed.choices and parsed.choices[1] and parsed.choices[1].message then
    local raw_content = parsed.choices[1].message.content
    local code = extract_code(raw_content)
    flog.info("copilot.response", string.format( -- TODO: remove after debugging
      "OK: raw_len=%d extracted_len=%d", #(raw_content or ""), #(code or "")
    ))
    return {
      code = code,
      error = nil,
      usage = {
        prompt_tokens = usage.prompt_tokens or 0,
        completion_tokens = usage.completion_tokens or 0,
        cached_tokens = usage.prompt_tokens_details
            and usage.prompt_tokens_details.cached_tokens
          or 0,
      },
      rate_limited = false,
    }
  end

  flog.warn("copilot.response", "no choices in response") -- TODO: remove after debugging
  return { code = nil, error = "No content in Copilot response", usage = nil, rate_limited = false }
end

return parse
