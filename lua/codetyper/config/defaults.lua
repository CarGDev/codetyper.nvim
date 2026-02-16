---@mod codetyper.config Configuration module for Codetyper.nvim

local M = {}

---@type CoderConfig
local defaults = {
  llm = {
    provider = "ollama", -- Options: "ollama", "openai", "gemini", "copilot"
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
      model = "claude-sonnet-4", -- Uses GitHub Copilot authentication
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
  auto_index = false, -- Auto-create coder companion files on file open
  indexer = {
    enabled = true, -- Enable project indexing
    auto_index = true, -- Index files on save
    index_on_open = false, -- Index project when opening
    max_file_size = 100000, -- Skip files larger than 100KB
    excluded_dirs = { "node_modules", "dist", "build", ".git", ".coder", "__pycache__", "vendor", "target" },
    index_extensions = { "lua", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb", "java", "c", "cpp", "h", "hpp" },
    memory = {
      enabled = true, -- Enable memory persistence
      max_memories = 1000, -- Maximum stored memories
      prune_threshold = 0.1, -- Remove low-weight memories
    },
  },
  brain = {
    enabled = true, -- Enable brain learning system
    auto_learn = true, -- Auto-learn from events
    auto_commit = true, -- Auto-commit after threshold
    commit_threshold = 10, -- Changes before auto-commit
    max_nodes = 5000, -- Maximum nodes before pruning
    max_deltas = 500, -- Maximum delta history
    prune = {
      enabled = true, -- Enable auto-pruning
      threshold = 0.1, -- Remove nodes below this weight
      unused_days = 90, -- Remove unused nodes after N days
    },
    output = {
      max_tokens = 4000, -- Token budget for LLM context
      format = "compact", -- "compact"|"json"|"natural"
    },
  },
  suggestion = {
    enabled = true, -- Enable ghost text suggestions (Copilot-style)
    auto_trigger = true, -- Auto-trigger on typing
    debounce = 150, -- Debounce in milliseconds
    use_copilot = true, -- Use copilot.lua suggestions when available, fallback to codetyper
    keymap = {
      accept = "<Tab>", -- Accept suggestion
      next = "<M-]>", -- Next suggestion (Alt+])
      prev = "<M-[>", -- Previous suggestion (Alt+[)
      dismiss = "<C-]>", -- Dismiss suggestion (Ctrl+])
    },
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

  local valid_providers = { "ollama", "openai", "gemini", "copilot" }
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
  if config.llm.provider == "openai" then
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
