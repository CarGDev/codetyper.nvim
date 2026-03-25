--- Show LLM accuracy statistics
local function cmd_llm_stats()
  local llm = require("codetyper.core.llm")
  local stats = llm.get_accuracy_stats()

  local lines = {
    "LLM Provider Accuracy Statistics",
    "================================",
    "",
    string.format("Ollama:"),
    string.format("  Total requests: %d", stats.ollama.total),
    string.format("  Correct: %d", stats.ollama.correct),
    string.format("  Accuracy: %.1f%%", stats.ollama.accuracy * 100),
    "",
    string.format("Copilot:"),
    string.format("  Total requests: %d", stats.copilot.total),
    string.format("  Correct: %d", stats.copilot.correct),
    string.format("  Accuracy: %.1f%%", stats.copilot.accuracy * 100),
    "",
    "Note: Smart selection prefers Ollama when brain memories",
    "provide enough context. Accuracy improves over time via",
    "pondering (verification with other LLMs).",
  }

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return cmd_llm_stats
