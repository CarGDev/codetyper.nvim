--- Model capabilities — context sizes, features, and Copilot request multipliers
--- Source: GitHub Copilot model picker (VS Code)
--- Updated: 2026-03-29
--- This file is the fallback when the /models API is unavailable.
--- Fields:
---   input    = max input/prompt tokens (K = x1000)
---   output   = max output tokens (K = x1000)
---   tools    = supports tool_calls
---   vision   = supports vision/image input
---   mult     = Copilot request multiplier (premium cost factor, 0 = free tier)

local M = {}

M.models = {
  -- Claude models
  ["claude-haiku-4.5"]       = { input = 128000, output = 32000,  tools = true,  vision = true,  mult = 0.33 },
  ["claude-opus-4.5"]        = { input = 128000, output = 32000,  tools = true,  vision = true,  mult = 3 },
  ["claude-opus-4.6"]        = { input = 128000, output = 64000,  tools = true,  vision = true,  mult = 3 },
  ["claude-sonnet-4"]        = { input = 128000, output = 16000,  tools = true,  vision = true,  mult = 1 },
  ["claude-sonnet-4.5"]      = { input = 128000, output = 32000,  tools = true,  vision = true,  mult = 1 },
  ["claude-sonnet-4.6"]      = { input = 128000, output = 32000,  tools = true,  vision = true,  mult = 1 },

  -- Gemini models
  ["gemini-2.5-pro"]         = { input = 109000, output = 64000,  tools = true,  vision = true,  mult = 1 },
  ["gemini-3-flash"]         = { input = 109000, output = 64000,  tools = true,  vision = true,  mult = 0.33 },
  ["gemini-3.1-pro"]         = { input = 109000, output = 64000,  tools = true,  vision = true,  mult = 1 },

  -- GPT-4 series
  ["gpt-4.1"]                = { input = 111000, output = 16000,  tools = true,  vision = true,  mult = 0 },
  ["gpt-4o"]                 = { input = 64000,  output = 4000,   tools = true,  vision = true,  mult = 0 },

  -- GPT-5 series
  ["gpt-5-mini"]             = { input = 128000, output = 64000,  tools = true,  vision = true,  mult = 0 },
  ["gpt-5.1"]                = { input = 128000, output = 64000,  tools = true,  vision = true,  mult = 1 },
  ["gpt-5.1-codex"]          = { input = 128000, output = 128000, tools = true,  vision = true,  mult = 1 },
  ["gpt-5.1-codex-max"]      = { input = 128000, output = 128000, tools = true,  vision = true,  mult = 1 },
  ["gpt-5.1-codex-mini"]     = { input = 128000, output = 128000, tools = true,  vision = true,  mult = 0.33 },
  ["gpt-5.2"]                = { input = 128000, output = 64000,  tools = true,  vision = true,  mult = 1 },
  ["gpt-5.2-codex"]          = { input = 272000, output = 128000, tools = true,  vision = true,  mult = 1 },
  ["gpt-5.3-codex"]          = { input = 272000, output = 128000, tools = true,  vision = true,  mult = 1 },
  ["gpt-5.4"]                = { input = 272000, output = 128000, tools = true,  vision = true,  mult = 1 },
  ["gpt-5.4-mini"]           = { input = 272000, output = 128000, tools = true,  vision = true,  mult = 0.33 },

  -- Other models
  ["grok-code-fast-1"]       = { input = 109000, output = 64000,  tools = true,  vision = false, mult = 0.25 },
  ["raptor-mini"]            = { input = 200000, output = 64000,  tools = true,  vision = true,  mult = 0 },

  -- O-series reasoning
  ["o3"]                     = { input = 200000, output = 100000, tools = true,  vision = true,  mult = 1 },
  ["o3-pro"]                 = { input = 200000, output = 100000, tools = true,  vision = true,  mult = 3 },
  ["o4-mini"]                = { input = 200000, output = 100000, tools = true,  vision = true,  mult = 0.33 },

  -- Copilot default (free tier)
  ["copilot"]                = { input = 64000,  output = 4000,   tools = false, vision = false, mult = 0 },
}

--- Get capabilities for a model (with normalize fallback)
---@param model string Model name (raw or normalized)
---@return table|nil { input, output, tools, vision, mult }
function M.get(model)
  if M.models[model] then
    return M.models[model]
  end
  -- Try lowercase
  local lower = model:lower()
  if M.models[lower] then
    return M.models[lower]
  end
  -- Try with normalize_model
  local ok, normalize = pcall(require, "codetyper.handler.normalize_model")
  if ok then
    local normalized = normalize(model)
    if M.models[normalized] then
      return M.models[normalized]
    end
  end
  return nil
end

--- Get max context size to use in prompts for a model
---@param model string
---@return number max_input_chars Approximate max chars to include in prompt
function M.get_prompt_limit(model)
  local caps = M.get(model)
  if not caps then
    return 8000 -- conservative default
  end
  -- Approximate 1 token = 4 chars, use 80% of max input to leave room for system prompt
  return math.floor(caps.input * 4 * 0.8)
end

return M
