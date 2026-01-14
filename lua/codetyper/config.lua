---@mod codetyper.config Configuration module for Codetyper.nvim

local M = {}

---@type CoderConfig
local defaults = {
  llm = {
    provider = "ollama", -- Options: "claude", "ollama", "openai", "gemini", "copilot"
    claude = {
      api_key = nil, -- Will use ANTHROPIC_API_KEY env var if nil
      model = "claude-sonnet-4-20250514",
    },
    ollama = {
      host = "http://localhost:11434",
      model = "deepseek-coder:6.7b",
    },
    openai = {
      api_key = nil, -- Will use OPENAI_API_KEY env var if nil
      model = "gpt-4o",
      endpoint = nil, -- Custom endpoint (Azure, OpenRouter, etc.)
    },
    gemini = {
      api_key = nil, -- Will use GEMINI_API_KEY env var if nil
      model = "gemini-2.0-flash",
    },
    copilot = {
      model = "gpt-4o", -- Uses GitHub Copilot authentication
    },
  },
  window = {
    width = 25, -- 25% of screen width (1/4)
    position = "left",
    border = "rounded",
  },
  patterns = {
    open_tag = "/@",
    close_tag = "@/",
    file_pattern = "*.coder.*",
  },
  auto_gitignore = true,
  auto_open_ask = true, -- Auto-open Ask panel on startup
  auto_index = false, -- Auto-create coder companion files on file open
  scheduler = {
    enabled = true, -- Enable event-driven scheduler
    ollama_scout = true, -- Use Ollama as fast local scout for first attempt
    escalation_threshold = 0.7, -- Below this confidence, escalate to remote LLM
    max_concurrent = 2, -- Maximum concurrent workers
    completion_delay_ms = 100, -- Wait after completion popup closes
  },
}

--- Deep merge two tables
---@param t1 table Base table
---@param t2 table Table to merge into base
---@return table Merged table
local function deep_merge(t1, t2)
  local result = vim.deepcopy(t1)
  for k, v in pairs(t2) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

--- Setup configuration with user options
---@param opts? CoderConfig User configuration options
---@return CoderConfig Final configuration
function M.setup(opts)
  opts = opts or {}
  return deep_merge(defaults, opts)
end

--- Get default configuration
---@return CoderConfig Default configuration
function M.get_defaults()
  return vim.deepcopy(defaults)
end

--- Validate configuration
---@param config CoderConfig Configuration to validate
---@return boolean, string? Valid status and optional error message
function M.validate(config)
  if not config.llm then
    return false, "Missing LLM configuration"
  end

  local valid_providers = { "claude", "ollama", "openai", "gemini", "copilot" }
  local is_valid_provider = false
  for _, p in ipairs(valid_providers) do
    if config.llm.provider == p then
      is_valid_provider = true
      break
    end
  end

  if not is_valid_provider then
    return false, "Invalid LLM provider. Must be one of: " .. table.concat(valid_providers, ", ")
  end

  -- Validate provider-specific configuration
  if config.llm.provider == "claude" then
    local api_key = config.llm.claude.api_key or vim.env.ANTHROPIC_API_KEY
    if not api_key or api_key == "" then
      return false, "Claude API key not configured. Set llm.claude.api_key or ANTHROPIC_API_KEY env var"
    end
  elseif config.llm.provider == "openai" then
    local api_key = config.llm.openai.api_key or vim.env.OPENAI_API_KEY
    if not api_key or api_key == "" then
      return false, "OpenAI API key not configured. Set llm.openai.api_key or OPENAI_API_KEY env var"
    end
  elseif config.llm.provider == "gemini" then
    local api_key = config.llm.gemini.api_key or vim.env.GEMINI_API_KEY
    if not api_key or api_key == "" then
      return false, "Gemini API key not configured. Set llm.gemini.api_key or GEMINI_API_KEY env var"
    end
  end
  -- Note: copilot uses OAuth from copilot.lua/copilot.vim, validated at runtime
  -- Note: ollama doesn't require API key, just host configuration

  return true
end

return M
