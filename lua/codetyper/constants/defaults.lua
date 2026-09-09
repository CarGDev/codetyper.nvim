---@mod codetyper.config Configuration module for Codetyper.nvim

local M = {}

--- Relative path (from project root) to the cost/usage history file
M.COST_HISTORY_FILE = "/.codetyper/cost_history.json"

--- Providers supported by the common routing and catalog contracts.
M.SUPPORTED_PROVIDERS = { "ollama", "copilot", "claude", "openai" }

local SUPPORTED_PROVIDER_SET = {
  ollama = true,
  copilot = true,
  claude = true,
  openai = true,
}

local COMPANION_FILE_PATTERN = "*.codetyper.*"

---@type CoderConfig
local defaults = {
  llm = {
    provider = "copilot", -- Options: "ollama", "copilot", "claude", "openai"
    smart_selection = false, -- Try Ollama first if available, escalate to Copilot on failure/low confidence
    ollama = {
      host = "http://localhost:11434",
      model = "gemma4:26b",
      ask_model = nil, -- Optional: cheaper model for question/explain calls
    },
    copilot = {
      model = "claude-sonnet-5", -- Uses GitHub Copilot authentication
      ask_model = "gpt-5-mini", -- Cheaper model for question/explain calls
    },
    claude = {
      model = "claude-sonnet-4-5", -- Uses ANTHROPIC_API_KEY from the environment
      ask_model = "claude-3-5-haiku-20241022", -- Optional cheaper Anthropic model
    },
    openai = {
      model = "gpt-5.5", -- Uses the ChatGPT Plus/Pro subscription session
      ask_model = "gpt-5.4-mini", -- Optional verified subscription model
    },
  },
  auto_gitignore = false, -- Disabled - no longer creating project folders
  auto_index = false, -- Auto-create coder companion files on file open
  patterns = {
    open_tag = "/@", -- Opening tag for inline prompts
    close_tag = "@/", -- Closing tag for inline prompts
    file_pattern = COMPANION_FILE_PATTERN, -- Canonical dotted companion-file pattern
  },
  keymaps = {
    transform = "<leader>ctt",
    model = "<leader>ctm",
    terminal = "<leader>ter",
  },
  indexer = {
    enabled = true, -- Enable project indexing
    auto_index = true, -- Index files on save
    index_on_open = false, -- Index project when opening
    max_file_size = 100000, -- Skip files larger than 100KB
    excluded_dirs = { "node_modules", "dist", "build", ".git", "__pycache__", "vendor", "target" },
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
  if type(opts) ~= "table" then
    error("Codetyper configuration must be a table", 2)
  end

  local result = deep_merge(defaults, opts)
  local valid, validation_error = M.validate(result)
  if not valid then
    error("Invalid Codetyper configuration: " .. validation_error, 2)
  end
  return result
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
  if type(config) ~= "table" then
    return false, "Configuration must be a table"
  end

  if type(config.llm) ~= "table" then
    return false, "Missing LLM configuration"
  end

  if not SUPPORTED_PROVIDER_SET[config.llm.provider] then
    return false, "Invalid LLM provider. Must be one of: " .. table.concat(M.SUPPORTED_PROVIDERS, ", ")
  end

  for _, provider in ipairs(M.SUPPORTED_PROVIDERS) do
    local provider_config = config.llm[provider]
    if provider_config ~= nil and type(provider_config) ~= "table" then
      return false, provider .. " configuration must be a table"
    end
    if provider_config then
      for _, field in ipairs({ "model", "ask_model" }) do
        if provider_config[field] ~= nil and type(provider_config[field]) ~= "string" then
          return false, provider .. "." .. field .. " must be a string"
        end
      end
    end
  end

  if config.patterns ~= nil then
    if type(config.patterns) ~= "table" then
      return false, "patterns configuration must be a table"
    end
    if config.patterns.file_pattern ~= nil and config.patterns.file_pattern ~= COMPANION_FILE_PATTERN then
      return false, "patterns.file_pattern must be " .. COMPANION_FILE_PATTERN
    end
    for _, field in ipairs({ "open_tag", "close_tag" }) do
      if config.patterns[field] ~= nil and type(config.patterns[field]) ~= "string" then
        return false, "patterns." .. field .. " must be a string"
      end
    end
  end

  if config.keymaps ~= nil then
    if type(config.keymaps) ~= "table" then
      return false, "keymaps configuration must be a table"
    end
    for _, name in ipairs({ "transform", "model", "terminal" }) do
      local mapping = config.keymaps[name]
      if mapping ~= nil and mapping ~= false and type(mapping) ~= "string" and type(mapping) ~= "table" then
        return false, "keymaps." .. name .. " must be a string, table, or false"
      end
    end
  end

  return true
end

return M
