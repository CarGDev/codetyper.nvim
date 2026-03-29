--- Pondering — cross-validate Ollama with Copilot
local accuracy = require("codetyper.core.llm.selector.accuracy")

local AGREEMENT_THRESHOLD = 0.7
local PONDER_SAMPLE_RATE = 0.2

--- Check if we should ponder this response
---@param confidence number
---@return boolean
local function should_ponder(confidence)
  if confidence >= 0.4 and confidence < 0.7 then
    return true
  end
  if confidence >= 0.7 then
    return math.random() < PONDER_SAMPLE_RATE
  end
  return false
end

--- Calculate agreement between two responses (Jaccard + structural)
---@param response1 string
---@param response2 string
---@return number 0-1
local function calculate_agreement(response1, response2)
  local norm1 = response1:lower():gsub("%s+", " "):gsub("[^%w%s]", "")
  local norm2 = response2:lower():gsub("%s+", " "):gsub("[^%w%s]", "")

  local words1 = {}
  for word in norm1:gmatch("%w+") do
    words1[word] = (words1[word] or 0) + 1
  end

  local words2 = {}
  for word in norm2:gmatch("%w+") do
    words2[word] = (words2[word] or 0) + 1
  end

  local intersection = 0
  local union = 0

  for word, count1 in pairs(words1) do
    local count2 = words2[word] or 0
    intersection = intersection + math.min(count1, count2)
    union = union + math.max(count1, count2)
  end

  for word, count2 in pairs(words2) do
    if not words1[word] then
      union = union + count2
    end
  end

  if union == 0 then
    return 1.0
  end

  local struct_score = 0
  local fc1 = select(2, response1:gsub("function", ""))
  local fc2 = select(2, response2:gsub("function", ""))
  if fc1 > 0 or fc2 > 0 then
    struct_score = 1 - math.abs(fc1 - fc2) / math.max(fc1, fc2, 1)
  else
    struct_score = 1.0
  end

  return (intersection / union * 0.7) + (struct_score * 0.3)
end

--- Ponder: verify Ollama response with Copilot
---@param prompt string
---@param context table
---@param ollama_response string
---@param callback fun(result: table)
local function ponder(prompt, context, ollama_response, callback)
  local copilot = require("codetyper.core.llm.providers.copilot")

  copilot.generate(prompt, context, function(verifier_response, err)
    if err or not verifier_response then
      callback({
        ollama_response = ollama_response,
        verifier_response = "",
        agreement_score = 1.0,
        ollama_correct = true,
        feedback = "Verification unavailable, trusting Ollama",
      })
      return
    end

    local agreement = calculate_agreement(ollama_response, verifier_response)
    local ollama_correct = agreement >= AGREEMENT_THRESHOLD

    accuracy.record("ollama", ollama_correct)

    -- Learn from verification
    local ok_brain, brain = pcall(require, "codetyper.core.memory")
    if ok_brain and brain.is_initialized and brain.is_initialized() then
      pcall(function()
        brain.learn({
          type = "correction",
          summary = ollama_correct and "Ollama verified correct" or "Ollama needed correction",
          detail = string.format("Prompt: %s\nAgreement: %.0f%%", prompt:sub(1, 100), agreement * 100),
          weight = ollama_correct and 0.8 or 0.9,
          file = context.file_path,
        })
      end)
    end

    callback({
      ollama_response = ollama_response,
      verifier_response = verifier_response,
      agreement_score = agreement,
      ollama_correct = ollama_correct,
      feedback = string.format(
        "%s: %.0f%%",
        ollama_correct and "Agreement" or "Disagreement",
        (ollama_correct and agreement or (1 - agreement)) * 100
      ),
    })
  end)
end

return {
  should_ponder = should_ponder,
  ponder = ponder,
}
