---@mod codetyper.types Type definitions for Codetyper.nvim

---@class CoderConfig
---@field llm LLMConfig LLM provider configuration
---@field window WindowConfig Window configuration
---@field patterns PatternConfig Pattern configuration
---@field auto_gitignore boolean Auto-manage .gitignore

---@class LLMConfig
---@field provider "ollama" | "openai" | "gemini" | "copilot" The LLM provider to use
---@field ollama OllamaConfig Ollama-specific configuration
---@field openai OpenAIConfig OpenAI-specific configuration
---@field gemini GeminiConfig Gemini-specific configuration
---@field copilot CopilotConfig Copilot-specific configuration

---@class OllamaConfig
---@field host string Ollama host URL
---@field model string Ollama model to use

---@class OpenAIConfig
---@field api_key string | nil OpenAI API key (or env var OPENAI_API_KEY)
---@field model string OpenAI model to use
---@field endpoint string | nil Custom endpoint (Azure, OpenRouter, etc.)

---@class GeminiConfig
---@field api_key string | nil Gemini API key (or env var GEMINI_API_KEY)
---@field model string Gemini model to use

---@class CopilotConfig
---@field model string Copilot model to use

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
