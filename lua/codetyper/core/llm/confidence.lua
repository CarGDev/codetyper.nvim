---@mod codetyper.agent.confidence Response confidence scoring
---@brief [[
--- Scores LLM responses using heuristics to decide if escalation is needed.
--- Returns 0.0-1.0 where higher = more confident the response is good.
---@brief ]]

local M = {}

local params = require("codetyper.params.agents.confidence")

--- Heuristic weights (must sum to 1.0)
M.weights = params.weights

--- Uncertainty phrases that indicate low confidence
local uncertainty_phrases = params.uncertainty_phrases

--- Score based on response length relative to prompt
---@param response string
---@param prompt string
---@return number 0.0-1.0
local function score_length(response, prompt)
  local response_len = #response
  local prompt_len = #prompt

  -- Very short response to long prompt is suspicious
  if prompt_len > 50 and response_len < 20 then
    return 0.2
  end

  -- Response should generally be longer than prompt for code generation
  local ratio = response_len / math.max(prompt_len, 1)

  if ratio < 0.5 then
    return 0.3
  elseif ratio < 1.0 then
    return 0.6
  elseif ratio < 2.0 then
    return 0.8
  else
    return 1.0
  end
end

--- Score based on uncertainty phrases
---@param response string
---@return number 0.0-1.0
local function score_uncertainty(response)
  local lower = response:lower()
  local found = 0

  for _, phrase in ipairs(uncertainty_phrases) do
    if lower:find(phrase:lower(), 1, true) then
      found = found + 1
    end
  end

  -- More uncertainty phrases = lower score
  if found == 0 then
    return 1.0
  elseif found == 1 then
    return 0.7
  elseif found == 2 then
    return 0.5
  else
    return 0.2
  end
end

--- Score based on syntax completeness
---@param response string
---@return number 0.0-1.0
local function score_syntax(response)
  local score = 1.0

  -- Check bracket balance
  if not require("codetyper.support.utils").check_brackets(response) then
    score = score - 0.4
  end

  -- Check for common incomplete patterns

  -- Lua: unbalanced end/function
  local function_count = select(2, response:gsub("function%s*%(", ""))
    + select(2, response:gsub("function%s+%w+%(", ""))
  local end_count = select(2, response:gsub("%f[%w]end%f[%W]", ""))
  if function_count > end_count + 2 then
    score = score - 0.2
  end

  -- JavaScript/TypeScript: unclosed template literals
  local backtick_count = select(2, response:gsub("`", ""))
  if backtick_count % 2 ~= 0 then
    score = score - 0.2
  end

  -- String quotes balance
  local double_quotes = select(2, response:gsub('"', ""))
  local single_quotes = select(2, response:gsub("'", ""))
  -- Allow for escaped quotes by being lenient
  if double_quotes % 2 ~= 0 and not response:find('\\"') then
    score = score - 0.1
  end
  if single_quotes % 2 ~= 0 and not response:find("\\'") then
    score = score - 0.1
  end

  return math.max(0, score)
end

--- Score based on line repetition
---@param response string
---@return number 0.0-1.0
local function score_repetition(response)
  local lines = vim.split(response, "\n", { plain = true })
  if #lines < 3 then
    return 1.0
  end

  -- Count duplicate non-empty lines
  local seen = {}
  local duplicates = 0

  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if #trimmed > 10 then -- Only check substantial lines
      if seen[trimmed] then
        duplicates = duplicates + 1
      end
      seen[trimmed] = true
    end
  end

  local dup_ratio = duplicates / #lines

  if dup_ratio < 0.1 then
    return 1.0
  elseif dup_ratio < 0.2 then
    return 0.8
  elseif dup_ratio < 0.3 then
    return 0.5
  else
    return 0.2 -- High repetition = degraded output
  end
end

--- Detect whether a line looks like code based on structural signals.
---@param line string A trimmed line of text
---@return boolean
local function is_code_line(line)
  if #line < 3 then
    return true
  end
  if line:match("[{}%(%)%[%];=<>]") then
    return true
  end
  if line:match("^%s*[%-%+%*/#@]")
    or line:match("^%s*import%s")
    or line:match("^%s*export%s")
    or line:match("^%s*from%s")
    or line:match("^%s*require%s*%(")
    or line:match("^%s*local%s")
    or line:match("^%s*const%s")
    or line:match("^%s*let%s")
    or line:match("^%s*var%s")
    or line:match("^%s*function%s")
    or line:match("^%s*return%s")
    or line:match("^%s*if%s")
    or line:match("^%s*for%s")
    or line:match("^%s*while%s")
    or line:match("^%s*class%s")
    or line:match("^%s*interface%s")
    or line:match("^%s*type%s")
    or line:match("^%s*def%s")
    or line:match("^%s*end$")
  then
    return true
  end
  if line:match("^%s%s") then
    return true
  end
  local symbols = #(line:gsub("[%w%s]", ""))
  if symbols / #line > 0.15 then
    return true
  end
  return false
end

--- Score based on prose/explanation contamination
--- Uses structural code detection — any line that doesn't look like code
--- is counted as prose. High prose ratio = low confidence.
---@param response string
---@return number 0.0-1.0
local function score_prose(response)
  local lines = vim.split(response, "\n", { plain = true })
  local prose_lines = 0
  local total_lines = 0

  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if #trimmed > 15 then
      total_lines = total_lines + 1
      if not is_code_line(trimmed) then
        prose_lines = prose_lines + 1
      end
    end
  end

  if total_lines == 0 then
    return 1.0
  end

  local prose_ratio = prose_lines / total_lines

  if prose_ratio == 0 then
    return 1.0
  elseif prose_ratio < 0.1 then
    return 0.7
  elseif prose_ratio < 0.2 then
    return 0.5
  else
    return 0.2
  end
end

--- Score based on truncation indicators
---@param response string
---@return number 0.0-1.0
local function score_truncation(response)
  local score = 1.0

  -- Ends with ellipsis
  if response:match("%.%.%.$") then
    score = score - 0.5
  end

  -- Ends with incomplete comment
  if response:match("/%*[^*/]*$") then -- Unclosed /* comment
    score = score - 0.4
  end
  if response:match("<!%-%-[^>]*$") then -- Unclosed HTML comment
    score = score - 0.4
  end

  -- Ends mid-statement (common patterns)
  local trimmed = vim.trim(response)
  local last_char = trimmed:sub(-1)

  -- Suspicious endings
  if last_char == "=" or last_char == "," or last_char == "(" then
    score = score - 0.3
  end

  -- Very short last line after long response
  local lines = vim.split(response, "\n", { plain = true })
  if #lines > 5 then
    local last_line = vim.trim(lines[#lines])
    if #last_line < 5 and not last_line:match("^[%}%]%)%;end]") then
      score = score - 0.2
    end
  end

  return math.max(0, score)
end

---@class ConfidenceBreakdown
---@field length number
---@field uncertainty number
---@field syntax number
---@field repetition number
---@field truncation number
---@field prose number
---@field weighted_total number

--- Calculate confidence score for response
---@param response string The LLM response
---@param prompt string The original prompt
---@param context table|nil Additional context (unused for now)
---@return number confidence 0.0-1.0
---@return ConfidenceBreakdown breakdown Individual scores
function M.score(response, prompt, context)
  _ = context -- Reserved for future use

  if not response or #response == 0 then
    return 0,
      {
        length = 0,
        uncertainty = 0,
        syntax = 0,
        repetition = 0,
        truncation = 0,
        prose = 0,
        weighted_total = 0,
      }
  end

  local scores = {
    length = score_length(response, prompt or ""),
    uncertainty = score_uncertainty(response),
    syntax = score_syntax(response),
    repetition = score_repetition(response),
    truncation = score_truncation(response),
    prose = score_prose(response),
  }

  -- Calculate weighted total
  local weighted = 0
  for key, weight in pairs(M.weights) do
    weighted = weighted + (scores[key] * weight)
  end

  scores.weighted_total = weighted

  return weighted, scores
end

--- Check if response needs escalation
---@param confidence number
---@param threshold number|nil Default: 0.7
---@return boolean needs_escalation
function M.needs_escalation(confidence, threshold)
  threshold = threshold or 0.7
  return confidence < threshold
end

--- Get human-readable confidence level
---@param confidence number
---@return string
function M.level_name(confidence)
  if confidence >= 0.9 then
    return "excellent"
  elseif confidence >= 0.8 then
    return "good"
  elseif confidence >= 0.7 then
    return "acceptable"
  elseif confidence >= 0.5 then
    return "uncertain"
  else
    return "poor"
  end
end

--- Format breakdown for logging
---@param breakdown ConfidenceBreakdown
---@return string
function M.format_breakdown(breakdown)
  return string.format(
    "len:%.2f unc:%.2f syn:%.2f rep:%.2f tru:%.2f pro:%.2f = %.2f",
    breakdown.length,
    breakdown.uncertainty,
    breakdown.syntax,
    breakdown.repetition,
    breakdown.truncation,
    breakdown.prose or 1.0,
    breakdown.weighted_total
  )
end

return M
