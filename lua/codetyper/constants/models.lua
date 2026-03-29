local M = {}
--- Default model for savings comparison (what you'd pay if not using Ollama)
M.comparison_model = "gpt-4o"

--- Models considered "free" (Ollama, local, Copilot subscription)
M.free_models = {
  ["ollama"] = true,
  ["codellama"] = true,
  ["llama2"] = true,
  ["llama3"] = true,
  ["mistral"] = true,
  ["deepseek-coder"] = true,
  ["copilot"] = true,
}

return M
