---@mod codetyper.types Type definitions for Codetyper.nvim

---@class CoderConfig
---@field llm LLMConfig LLM provider configuration
---@field window WindowConfig Window configuration
---@field patterns PatternConfig Pattern configuration
---@field auto_gitignore boolean Auto-manage .gitignore

---@class LLMConfig
---@field provider "claude" | "ollama" The LLM provider to use
---@field claude ClaudeConfig Claude-specific configuration
---@field ollama OllamaConfig Ollama-specific configuration

---@class ClaudeConfig
---@field api_key string | nil Claude API key (or env var ANTHROPIC_API_KEY)
---@field model string Claude model to use

---@class OllamaConfig
---@field host string Ollama host URL
---@field model string Ollama model to use

---@class WindowConfig
---@field width number Width of the coder window (percentage or columns)
---@field position "left" | "right" Position of the coder window
---@field border string Border style for floating windows

---@class PatternConfig
---@field open_tag string Opening tag for prompts
---@field close_tag string Closing tag for prompts
---@field file_pattern string Pattern for coder files

---@class CoderPrompt
---@field content string The prompt content between tags
---@field start_line number Starting line number
---@field end_line number Ending line number
---@field start_col number Starting column
---@field end_col number Ending column

---@class CoderFile
---@field coder_path string Path to the .coder.* file
---@field target_path string Path to the target file
---@field filetype string The filetype/extension

return {}
