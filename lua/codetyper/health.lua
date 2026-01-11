---@mod codetyper.health Health check for Codetyper.nvim

local M = {}

local health = vim.health or require("health")

--- Run health checks
function M.check()
  health.start("Codetyper.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.8.0") == 1 then
    health.ok("Neovim version >= 0.8.0")
  else
    health.error("Neovim 0.8.0+ required")
  end

  -- Check if plugin is initialized
  local ok, codetyper = pcall(require, "codetyper")
  if ok and codetyper.is_initialized() then
    health.ok("Plugin initialized")
  else
    health.info("Plugin not yet initialized (call setup() first)")
  end

  -- Check curl availability
  if vim.fn.executable("curl") == 1 then
    health.ok("curl is available")
  else
    health.error("curl is required for LLM API calls")
  end

  -- Check LLM configuration
  if ok and codetyper.is_initialized() then
    local config = codetyper.get_config()

    health.info("LLM Provider: " .. config.llm.provider)

    if config.llm.provider == "claude" then
      local api_key = config.llm.claude.api_key or vim.env.ANTHROPIC_API_KEY
      if api_key and api_key ~= "" then
        health.ok("Claude API key configured")
      else
        health.warn("Claude API key not set. Set ANTHROPIC_API_KEY or llm.claude.api_key")
      end
      health.info("Claude model: " .. config.llm.claude.model)
    elseif config.llm.provider == "ollama" then
      health.info("Ollama host: " .. config.llm.ollama.host)
      health.info("Ollama model: " .. config.llm.ollama.model)

      -- Try to check Ollama connectivity
      local ollama = require("codetyper.llm.ollama")
      ollama.health_check(function(is_ok, err)
        if is_ok then
          vim.schedule(function()
            health.ok("Ollama is reachable")
          end)
        else
          vim.schedule(function()
            health.warn("Cannot connect to Ollama: " .. (err or "unknown error"))
          end)
        end
      end)
    end
  end

  -- Check optional dependencies
  if pcall(require, "telescope") then
    health.ok("telescope.nvim is available (enhanced file picker)")
  else
    health.info("telescope.nvim not found (using basic file picker)")
  end

  -- Check .gitignore configuration
  local utils = require("codetyper.utils")
  local gitignore = require("codetyper.gitignore")

  local root = utils.get_project_root()
  if root then
    health.info("Project root: " .. root)
    if gitignore.is_ignored() then
      health.ok("Coder files are in .gitignore")
    else
      health.warn("Coder files not in .gitignore (will be added on setup)")
    end
  else
    health.info("No project root detected")
  end
end

return M
