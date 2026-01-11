---@mod codetyper.config Configuration module for Codetyper.nvim

local M = {}

---@type CoderConfig
local defaults = {
  llm = {
    provider = "claude",
    claude = {
      api_key = nil, -- Will use ANTHROPIC_API_KEY env var if nil
      model = "claude-sonnet-4-20250514",
    },
    ollama = {
      host = "http://localhost:11434",
      model = "codellama",
    },
  },
  window = {
    width = 0.25, -- 25% of screen width (1/4)
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

  if config.llm.provider ~= "claude" and config.llm.provider ~= "ollama" then
    return false, "Invalid LLM provider. Must be 'claude' or 'ollama'"
  end

  if config.llm.provider == "claude" then
    local api_key = config.llm.claude.api_key or vim.env.ANTHROPIC_API_KEY
    if not api_key or api_key == "" then
      return false, "Claude API key not configured. Set llm.claude.api_key or ANTHROPIC_API_KEY env var"
    end
  end

  return true
end

return M
