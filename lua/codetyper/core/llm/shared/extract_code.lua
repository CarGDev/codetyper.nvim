--- Extract code from LLM response — strip markdown fences, explanations, special tokens

--- Parse LLM response and extract code
---@param response string Raw LLM response
---@return string Extracted code
local function extract_code(response)
  local code = response

  -- Remove markdown code blocks with language tags
  code = code:gsub("```%w+%s*\n", "")
  code = code:gsub("```%w+%s*$", "")
  code = code:gsub("^```%w*\n?", "")
  code = code:gsub("\n?```%s*$", "")
  code = code:gsub("\n```\n", "\n")
  code = code:gsub("```", "")

  -- Remove common explanation prefixes
  code = code:gsub("^Here.-:\n", "")
  code = code:gsub("^Here's.-:\n", "")
  code = code:gsub("^This.-:\n", "")
  code = code:gsub("^The following.-:\n", "")
  code = code:gsub("^Below.-:\n", "")

  -- Remove common explanation suffixes
  code = code:gsub("\n\nThis code.-$", "")
  code = code:gsub("\n\nThe above.-$", "")
  code = code:gsub("\n\nNote:.-$", "")
  code = code:gsub("\n\nExplanation:.-$", "")

  -- Trim whitespace
  code = code:match("^%s*(.-)%s*$") or code

  return code
end

return extract_code
