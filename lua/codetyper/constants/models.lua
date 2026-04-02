local M = {}

--- Default model for savings comparison (what you'd pay if not using Ollama)
M.comparison_model = "gpt-4o"

--- Models considered "free" (Ollama, local, Copilot subscription)
M.free_models = {
  ["ollama"] = true,
  ["codellama"] = true,
  ["llama2"] = true,
  ["llama3"] = true,
  ["mistral"] = true,
  ["deepseek-coder"] = true,
  ["copilot"] = true,
}

--- Hardcoded fallback cost multipliers (updated 2026-04-01).
--- API response billing.multiplier is preferred when available.
M.cost_multipliers = {
  -- Unlimited models (0x)
  ["gpt-4o"] = 0,
  ["gpt-4.1"] = 0,
  ["gpt-5-mini"] = 0,
  -- Low cost models
  ["claude-haiku-4.5"] = 0.33,
  ["gemini-3-flash-preview"] = 0.33,
  ["grok-code-fast-1"] = 0.25,
  -- Standard cost models (1.0x)
  ["claude-sonnet-4"] = 1.0,
  ["claude-sonnet-4.5"] = 1.0,
  ["claude-sonnet-4.6"] = 1.0,
  ["gemini-2.5-pro"] = 1.0,
  ["gemini-3.1-pro-preview"] = 1.0,
  ["gpt-5.1"] = 1.0,
  ["gpt-5.2"] = 1.0,
  -- Premium models (3.0x)
  ["claude-opus-4.5"] = 3.0,
  ["claude-opus-4.6"] = 3.0,
}

--- Unlimited models (0x cost multiplier)
M.unlimited_models = {
  ["gpt-4o"] = true,
  ["gpt-4.1"] = true,
  ["gpt-5-mini"] = true,
}

--- Hardcoded fallback context sizes (updated 2026-04-01 from Copilot API).
--- Used only when the API hasn't been fetched yet.
M.context_sizes = {
  ["gpt-4o"]                 = { input = 64000,  output = 4000 },
  ["gpt-4.1"]                = { input = 111000, output = 16000 },
  ["gpt-5-mini"]             = { input = 128000, output = 64000 },
  ["claude-haiku-4.5"]       = { input = 128000, output = 32000 },
  ["claude-sonnet-4"]        = { input = 128000, output = 16000 },
  ["claude-sonnet-4.5"]      = { input = 128000, output = 32000 },
  ["claude-sonnet-4.6"]      = { input = 128000, output = 32000 },
  ["claude-opus-4.5"]        = { input = 128000, output = 32000 },
  ["claude-opus-4.6"]        = { input = 128000, output = 64000 },
  ["gemini-2.5-pro"]         = { input = 109000, output = 64000 },
  ["gemini-3-flash-preview"] = { input = 109000, output = 64000 },
  ["gemini-3.1-pro-preview"] = { input = 109000, output = 64000 },
  ["gpt-5.1"]                = { input = 128000, output = 64000 },
  ["gpt-5.2"]                = { input = 128000, output = 64000 },
  ["grok-code-fast-1"]       = { input = 109000, output = 64000 },
}

M.default_context_size = { input = 128000, output = 16000 }

--- Fallback models when API is unavailable
M.fallback_models = {
  {
    id = "gpt-4o",
    name = "GPT-4o",
    max_output_tokens = 4000,
    max_input_tokens = 64000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 0,
    is_unlimited = true,
    picker_enabled = true,
  },
  {
    id = "gpt-5-mini",
    name = "GPT-5 mini",
    max_output_tokens = 64000,
    max_input_tokens = 128000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 0,
    is_unlimited = true,
    picker_enabled = true,
  },
  {
    id = "claude-sonnet-4",
    name = "Claude Sonnet 4",
    max_output_tokens = 16000,
    max_input_tokens = 128000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 1.0,
    is_unlimited = false,
    picker_enabled = true,
  },
  {
    id = "claude-sonnet-4.5",
    name = "Claude Sonnet 4.5",
    max_output_tokens = 16000,
    max_input_tokens = 128000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 1.0,
    is_unlimited = false,
    picker_enabled = true,
  },
  {
    id = "claude-opus-4.5",
    name = "Claude Opus 4.5",
    max_output_tokens = 16000,
    max_input_tokens = 128000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 3.0,
    is_unlimited = false,
    picker_enabled = true,
  },
  {
    id = "gpt-4.1",
    name = "GPT-4.1",
    max_output_tokens = 16000,
    max_input_tokens = 111000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 0,
    is_unlimited = true,
    picker_enabled = true,
  },
  {
    id = "gemini-2.5-pro",
    name = "Gemini 2.5 Pro",
    max_output_tokens = 64000,
    max_input_tokens = 109000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 1.0,
    is_unlimited = false,
    picker_enabled = true,
  },
  {
    id = "grok-code-fast-1",
    name = "Grok Code Fast 1",
    max_output_tokens = 64000,
    max_input_tokens = 109000,
    is_tool_capable = true,
    supports_streaming = true,
    cost_multiplier = 0.25,
    is_unlimited = false,
    picker_enabled = true,
  },
}

return M
