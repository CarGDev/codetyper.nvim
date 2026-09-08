--- Model capability tiers for prompt strategy selection
--- agent: tool-capable models — structured output, SEARCH/REPLACE, reasoning
--- chat: good instruction followers — one-shot, strict format, explicit boundaries
--- basic: code-completion-only — fill-in-the-middle, minimal prompt, raw code

local normalize_model = require("codetyper.handler.normalize_model")
local model_caps = require("codetyper.constants.model_caps")

--- Static fallback for models not in model_caps (Ollama, local models)
local static_tiers = {
  ["llama3"] = "chat",
  ["llama2"] = "chat",
  ["mistral"] = "chat",
  ["deepseek-coder"] = "basic",
  ["codellama"] = "basic",
}

--- Cache for API-detected tiers
local api_tiers = nil

--- Update tiers from Copilot API model data
---@param models table[] Models from copilot/models.lua fetch()
local function update_from_api(models)
  if not models then
    return
  end
  api_tiers = {}
  for _, model in ipairs(models) do
    local name = normalize_model(model.name or model.id)
    if model.is_tool_capable then
      api_tiers[name] = "agent"
    elseif model.max_input_tokens and model.max_input_tokens >= 32000 then
      api_tiers[name] = "chat"
    else
      api_tiers[name] = "basic"
    end
  end
end

--- Look up a tier for a normalized model name against api_tiers, model_caps,
--- and static_tiers, in that priority order. Returns nil (no default
--- applied) when nothing matches, so callers can retry with a different
--- name before falling back to a default tier.
---@param normalized string Already-normalized model name
---@return string|nil tier "agent" | "chat" | "basic" | nil
local function lookup_tier(normalized)
  -- API-detected tier (most accurate, from live /models endpoint)
  if api_tiers and api_tiers[normalized] then
    return api_tiers[normalized]
  end

  -- Derive from hardcoded model_caps (tools = agent, large context = chat)
  local caps = model_caps.get(normalized)
  if caps then
    if caps.tools then
      return "agent"
    end
    if caps.input and caps.input >= 32000 then
      return "chat"
    end
    return "basic"
  end

  -- Static fallback (Ollama/local models)
  if static_tiers[normalized] then
    return static_tiers[normalized]
  end

  return nil
end

--- Get tier for a model name
--- Priority: API-detected → model_caps (tools field) → static map →
--- same lookup chain again against the ":tag"-stripped name → default "chat"
---@param model string Raw model name
---@return string tier "agent" | "chat" | "basic"
local function get_tier(model)
  local normalized = normalize_model(model)

  local tier = lookup_tier(normalized)
  if tier then
    return tier
  end

  -- Strip a trailing Ollama-style ":tag" (e.g. "llama3:8b" -> "llama3",
  -- "gemma4:26b" -> "gemma4") and retry the same lookup chain before
  -- defaulting. A model MUST NOT be classified "basic" purely because its
  -- raw name contains a colon — that heuristic previously misclassified
  -- any unknown tagged model (including this plugin's own default
  -- "gemma4:26b") into the weakest tier.
  local stripped = normalized:match("^([^:]+):")
  if stripped then
    tier = lookup_tier(stripped)
    if tier then
      return tier
    end
  end

  return "chat"
end

return {
  get_tier = get_tier,
  update_from_api = update_from_api,
}
