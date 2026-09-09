---@mod codetyper.types Type definitions for Codetyper.nvim

---@class CoderConfig
---@field llm LLMConfig LLM provider configuration
---@field window WindowConfig Window configuration
---@field patterns PatternConfig Pattern configuration
---@field keymaps KeymapConfig Configurable keymaps; false disables one mapping
---@field auto_gitignore boolean Auto-manage .gitignore

---@class LLMConfig
---@field provider "ollama" | "copilot" | "claude" | "openai" The LLM provider to use
---@field ollama OllamaConfig Ollama-specific configuration
---@field copilot CopilotConfig Copilot-specific configuration
---@field claude ClaudeConfig Anthropic-specific configuration
---@field openai OpenAIConfig ChatGPT Plus/Pro subscription configuration

---@class OllamaConfig
---@field host string Ollama host URL
---@field model string Ollama model to use
---@field ask_model string|nil Optional cheaper model for questions

---@class CopilotConfig
---@field model string Copilot model to use
---@field ask_model string|nil Optional cheaper model for questions

---@class ClaudeConfig
---@field model string Anthropic model to use
---@field ask_model string|nil Optional cheaper model for questions

---@class OpenAIConfig
---@field model string ChatGPT subscription model to use
---@field ask_model string|nil Optional verified subscription model for questions

---@class WindowConfig
---@field width number Width of the coder window (percentage or columns)
---@field position "left" | "right" Position of the coder window
---@field border string Border style for floating windows

---@class PatternConfig
---@field open_tag string Opening tag for prompts
---@field close_tag string Closing tag for prompts
---@field file_pattern string Pattern for coder files

---@class KeymapConfig
---@field transform string|table|false Transform mapping override or disabled state
---@field model string|table|false Model mapping override or disabled state
---@field terminal string|table|false Terminal mapping override or disabled state

---@class CoderPrompt
---@field content string The prompt content between tags
---@field start_line number Starting line number
---@field end_line number Ending line number
---@field start_col number Starting column
---@field end_col number Ending column

---@class CoderFile
---@field coder_path string Path to the *.codetyper.* companion file
---@field target_path string Path to the target file
---@field filetype string The filetype/extension

return {}
