--- Model pricing table (per 1M tokens in USD)
---@type table<string, {input: number, cached_input: number|nil, output: number|nil}>
local pricing = {
  -- GPT-5.x series
  ["gpt-5.2"] = { input = 1.75, cached_input = 0.175, output = 14.00 },
  ["gpt-5.1"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5-mini"] = { input = 0.25, cached_input = 0.025, output = 2.00 },
  ["gpt-5-nano"] = { input = 0.05, cached_input = 0.005, output = 0.40 },
  ["gpt-5.2-chat-latest"] = { input = 1.75, cached_input = 0.175, output = 14.00 },
  ["gpt-5.1-chat-latest"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5-chat-latest"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5.2-codex"] = { input = 1.75, cached_input = 0.175, output = 14.00 },
  ["gpt-5.1-codex-max"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5.1-codex"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5-codex"] = { input = 1.25, cached_input = 0.125, output = 10.00 },
  ["gpt-5.2-pro"] = { input = 21.00, cached_input = nil, output = 168.00 },
  ["gpt-5-pro"] = { input = 15.00, cached_input = nil, output = 120.00 },
  ["gpt-5.1-codex-mini"] = { input = 0.25, cached_input = 0.025, output = 2.00 },
  ["gpt-5-search-api"] = { input = 1.25, cached_input = 0.125, output = 10.00 },

  -- GPT-4.x series
  ["gpt-4.1"] = { input = 2.00, cached_input = 0.50, output = 8.00 },
  ["gpt-4.1-mini"] = { input = 0.40, cached_input = 0.10, output = 1.60 },
  ["gpt-4.1-nano"] = { input = 0.10, cached_input = 0.025, output = 0.40 },
  ["gpt-4o"] = { input = 2.50, cached_input = 1.25, output = 10.00 },
  ["gpt-4o-2024-05-13"] = { input = 5.00, cached_input = nil, output = 15.00 },
  ["gpt-4o-mini"] = { input = 0.15, cached_input = 0.075, output = 0.60 },

  -- Realtime models
  ["gpt-realtime"] = { input = 4.00, cached_input = 0.40, output = 16.00 },
  ["gpt-realtime-mini"] = { input = 0.60, cached_input = 0.06, output = 2.40 },
  ["gpt-4o-realtime-preview"] = { input = 5.00, cached_input = 2.50, output = 20.00 },
  ["gpt-4o-mini-realtime-preview"] = { input = 0.60, cached_input = 0.30, output = 2.40 },

  -- Audio models
  ["gpt-audio"] = { input = 2.50, cached_input = nil, output = 10.00 },
  ["gpt-audio-mini"] = { input = 0.60, cached_input = nil, output = 2.40 },
  ["gpt-4o-audio-preview"] = { input = 2.50, cached_input = nil, output = 10.00 },
  ["gpt-4o-mini-audio-preview"] = { input = 0.15, cached_input = nil, output = 0.60 },

  -- O-series reasoning models
  ["o1"] = { input = 15.00, cached_input = 7.50, output = 60.00 },
  ["o1-pro"] = { input = 150.00, cached_input = nil, output = 600.00 },
  ["o3-pro"] = { input = 20.00, cached_input = nil, output = 80.00 },
  ["o3"] = { input = 2.00, cached_input = 0.50, output = 8.00 },
  ["o3-deep-research"] = { input = 10.00, cached_input = 2.50, output = 40.00 },
  ["o4-mini"] = { input = 1.10, cached_input = 0.275, output = 4.40 },
  ["o4-mini-deep-research"] = { input = 2.00, cached_input = 0.50, output = 8.00 },
  ["o3-mini"] = { input = 1.10, cached_input = 0.55, output = 4.40 },
  ["o1-mini"] = { input = 1.10, cached_input = 0.55, output = 4.40 },

  -- Codex
  ["codex-mini-latest"] = { input = 1.50, cached_input = 0.375, output = 6.00 },

  -- Search models
  ["gpt-4o-mini-search-preview"] = { input = 0.15, cached_input = nil, output = 0.60 },
  ["gpt-4o-search-preview"] = { input = 2.50, cached_input = nil, output = 10.00 },

  -- Computer use
  ["computer-use-preview"] = { input = 3.00, cached_input = nil, output = 12.00 },

  -- Image models
  ["gpt-image-1.5"] = { input = 5.00, cached_input = 1.25, output = 10.00 },
  ["chatgpt-image-latest"] = { input = 5.00, cached_input = 1.25, output = 10.00 },
  ["gpt-image-1"] = { input = 5.00, cached_input = 1.25, output = nil },
  ["gpt-image-1-mini"] = { input = 2.00, cached_input = 0.20, output = nil },

  -- Claude models
  ["claude-3-opus"] = { input = 15.00, cached_input = 7.50, output = 75.00 },
  ["claude-3-sonnet"] = { input = 3.00, cached_input = 1.50, output = 15.00 },
  ["claude-3-haiku"] = { input = 0.25, cached_input = 0.125, output = 1.25 },
  ["claude-3.5-sonnet"] = { input = 3.00, cached_input = 1.50, output = 15.00 },
  ["claude-3.5-haiku"] = { input = 0.80, cached_input = 0.40, output = 4.00 },

  -- Ollama/Local models (free)
  ["ollama"] = { input = 0, cached_input = 0, output = 0 },
  ["codellama"] = { input = 0, cached_input = 0, output = 0 },
  ["llama2"] = { input = 0, cached_input = 0, output = 0 },
  ["llama3"] = { input = 0, cached_input = 0, output = 0 },
  ["mistral"] = { input = 0, cached_input = 0, output = 0 },
  ["deepseek-coder"] = { input = 0, cached_input = 0, output = 0 },

  -- Copilot (included in subscription, but tracking usage)
  ["copilot"] = { input = 0, cached_input = 0, output = 0 },
}

return pricing
