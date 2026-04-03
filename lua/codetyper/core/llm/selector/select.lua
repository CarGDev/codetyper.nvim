--- Provider selection logic — pick Ollama vs Copilot based on context
local accuracy = require("codetyper.core.llm.selector.accuracy")

local MIN_MEMORIES_FOR_LOCAL = 3
local MIN_RELEVANCE_FOR_LOCAL = 0.6

local function get_brain()
  local ok, brain = pcall(require, "codetyper.core.memory")
  if ok and brain.is_initialized and brain.is_initialized() then
    return brain
  end
  return nil
end

--- Query brain for relevant context
---@param prompt string
---@param file_path string|nil
---@return table { memories, relevance, count }
local function query_brain_context(prompt, file_path)
  local result = { memories = {}, relevance = 0, count = 0 }
  local brain = get_brain()
  if not brain then
    return result
  end

  local ok, query_result = pcall(function()
    return brain.query({
      query = prompt,
      file = file_path,
      limit = 10,
      types = { "pattern", "correction", "convention", "fact" },
    })
  end)

  if not ok or not query_result then
    return result
  end

  result.memories = query_result.nodes or {}
  result.count = #result.memories

  if result.count > 0 then
    local total_relevance = 0
    for _, node in ipairs(result.memories) do
      local node_relevance = (node.sc and node.sc.w or 0.5) * (node.sc and node.sc.sr or 0.5)
      total_relevance = total_relevance + node_relevance
    end
    result.relevance = total_relevance / result.count
  end

  return result
end

--- Check if Ollama is configured (has host set)
---@return boolean
local function is_ollama_configured()
  local ok, codetyper = pcall(require, "codetyper")
  if not ok then return false end
  local config = codetyper.get_config()
  return config and config.llm and config.llm.ollama and config.llm.ollama.host ~= nil
end

--- Select the best provider
--- Strategy: default to Ollama if configured (free, local), fall back to Copilot.
--- Brain memories boost confidence but are NOT required for Ollama selection.
---@param prompt string
---@param context table
---@return table SelectionResult
local function select_provider(prompt, context)
  accuracy.load()

  local file_path = context.file_path
  local brain_context = query_brain_context(prompt, file_path)

  local memory_confidence = 0
  if brain_context.count >= MIN_MEMORIES_FOR_LOCAL then
    memory_confidence = math.min(1.0, brain_context.count / 10) * brain_context.relevance
  end

  local historical_confidence = accuracy.get_ollama_confidence()
  local combined_confidence = (memory_confidence * 0.6) + (historical_confidence * 0.4)

  local provider = "copilot"
  local reason = ""

  -- Default to Ollama if configured — it's free and local.
  -- Brain memories and historical accuracy boost confidence for pondering decisions,
  -- but Ollama is always tried first when available.
  if is_ollama_configured() then
    provider = "ollama"
    if brain_context.count >= MIN_MEMORIES_FOR_LOCAL and combined_confidence >= MIN_RELEVANCE_FOR_LOCAL then
      reason = string.format(
        "Ollama + rich context: %d memories (%.0f%% relevance), historical: %.0f%%",
        brain_context.count, brain_context.relevance * 100, historical_confidence * 100
      )
      -- High confidence — less likely to ponder
      combined_confidence = math.max(combined_confidence, 0.7)
    elseif brain_context.count > 0 then
      reason = string.format("Ollama + moderate context: %d memories, will verify if needed", brain_context.count)
      combined_confidence = math.max(combined_confidence, 0.4)
    else
      reason = "Ollama first (free, local) — will escalate on failure or low confidence"
      -- Low confidence triggers pondering/verification with Copilot
      combined_confidence = 0.3
    end
  else
    reason = "Ollama not configured, using Copilot"
    combined_confidence = 0.9
  end

  return {
    provider = provider,
    confidence = combined_confidence,
    memory_count = brain_context.count,
    reason = reason,
    memories = brain_context.memories,
  }
end

return select_provider
