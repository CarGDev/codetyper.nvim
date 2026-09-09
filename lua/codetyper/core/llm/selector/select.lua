--- Provider selection logic — preserve explicit providers, otherwise use the
--- central Copilot-first/Ollama-fallback resolver.
local accuracy = require("codetyper.core.llm.selector.accuracy")
local provider_resolver = require("codetyper.core.llm.provider_resolver")

local MIN_MEMORIES_FOR_LOCAL = 3
local MIN_RELEVANCE_FOR_LOCAL = 0.6

local function tool_mode(context, provider)
  local capabilities = context and context.tool_capabilities
  if type(capabilities) ~= "table" then
    return "none"
  end
  if provider == "copilot"
    and context.is_project_task == true
    and capabilities.native_tools == true
    and (capabilities.provider == nil or capabilities.provider == "copilot")
  then
    return "native"
  end
  if capabilities.marker_tools == true then
    return "marker"
  end
  return "none"
end

---@param context table|nil
---@return string|nil
local function explicit_provider(context)
  if not context then
    return nil
  end
  return context.provider or context.provider_name or context.llm_provider
end

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

--- Select the best provider
--- Strategy: Copilot-first, auth-gated. Ollama is only selected when
--- Copilot authentication is invalid/unavailable (see provider_resolver).
--- Brain memories and historical accuracy only affect pondering/verification
--- confidence when Ollama ends up being the active provider — they never
--- cause Ollama to be preferred over an authenticated Copilot.
---@param prompt string
---@param context table
---@return table SelectionResult
local function select_provider(prompt, context)
  context = context or {}
  local requested_provider = explicit_provider(context)
  if requested_provider then
    local valid, validation_error = provider_resolver.validate_provider(requested_provider)
    if not valid then
      return {
        provider = requested_provider,
        explicit = true,
        confidence = 0,
        memory_count = 0,
        reason = validation_error,
        memories = {},
        error = validation_error,
        tool_mode = "none",
      }
    end

    return {
      provider = requested_provider,
      explicit = true,
      confidence = 1.0,
      memory_count = 0,
      reason = "Explicit provider: " .. requested_provider,
      memories = {},
      tool_mode = tool_mode(context, requested_provider),
    }
  end

  accuracy.load()

  local file_path = context.file_path
  local brain_context = query_brain_context(prompt, file_path)

  local memory_confidence = 0
  if brain_context.count >= MIN_MEMORIES_FOR_LOCAL then
    memory_confidence = math.min(1.0, brain_context.count / 10) * brain_context.relevance
  end

  local historical_confidence = accuracy.get_ollama_confidence()
  local combined_confidence = (memory_confidence * 0.6) + (historical_confidence * 0.4)

  local configured_provider = provider_resolver.get_explicit_provider and provider_resolver.get_explicit_provider() or nil
  local provider = provider_resolver.resolve_sync()
  local is_explicit = configured_provider ~= nil and configured_provider == provider
  local reason = ""

  if provider == "ollama" then
    if is_explicit then
      reason = "Explicit provider: ollama"
      combined_confidence = 1.0
    elseif brain_context.count >= MIN_MEMORIES_FOR_LOCAL and combined_confidence >= MIN_RELEVANCE_FOR_LOCAL then
      reason = string.format(
        "Copilot unavailable, using Ollama + rich context: %d memories (%.0f%% relevance), historical: %.0f%%",
        brain_context.count, brain_context.relevance * 100, historical_confidence * 100
      )
      -- High confidence — less likely to ponder
      combined_confidence = math.max(combined_confidence, 0.7)
    elseif brain_context.count > 0 then
      reason = string.format("Copilot unavailable, using Ollama + moderate context: %d memories, will verify if needed", brain_context.count)
      combined_confidence = math.max(combined_confidence, 0.4)
    else
      reason = "Copilot unavailable, using Ollama — will escalate on failure or low confidence"
      -- Low confidence triggers pondering/verification with Copilot (if it recovers)
      combined_confidence = 0.3
    end
  else
    reason = is_explicit and ("Explicit provider: " .. provider) or "Copilot authenticated — using Copilot"
    combined_confidence = 0.9
  end

  return {
    provider = provider,
    explicit = is_explicit,
    confidence = combined_confidence,
    memory_count = brain_context.count,
    reason = reason,
    memories = brain_context.memories,
    tool_mode = tool_mode(context, provider),
  }
end

return select_provider
