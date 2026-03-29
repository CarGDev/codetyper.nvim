--- Provider accuracy tracking — persisted in brain
local M = {}

local accuracy_cache = {
  ollama = { correct = 0, total = 0 },
  copilot = { correct = 0, total = 0 },
}

local function get_brain()
  local ok, brain = pcall(require, "codetyper.core.memory")
  if ok and brain.is_initialized and brain.is_initialized() then
    return brain
  end
  return nil
end

function M.load()
  local brain = get_brain()
  if not brain then
    return
  end
  pcall(function()
    local result = brain.query({
      query = "provider_accuracy_stats",
      types = { "metric" },
      limit = 1,
    })
    if result and result.nodes and #result.nodes > 0 then
      local node = result.nodes[1]
      if node.c and node.c.d then
        local ok, stats = pcall(vim.json.decode, node.c.d)
        if ok and stats then
          accuracy_cache = stats
        end
      end
    end
  end)
end

function M.save()
  local brain = get_brain()
  if not brain then
    return
  end
  pcall(function()
    brain.learn({
      type = "metric",
      summary = "provider_accuracy_stats",
      detail = vim.json.encode(accuracy_cache),
      weight = 1.0,
    })
  end)
end

function M.get_ollama_confidence()
  local stats = accuracy_cache.ollama
  if stats.total < 5 then
    return 0.5
  end
  return math.min(1.0, (stats.correct / stats.total) * 1.2)
end

function M.record(provider, was_correct)
  if accuracy_cache[provider] then
    accuracy_cache[provider].total = accuracy_cache[provider].total + 1
    if was_correct then
      accuracy_cache[provider].correct = accuracy_cache[provider].correct + 1
    end
    M.save()
  end
end

function M.get_stats()
  return {
    ollama = {
      correct = accuracy_cache.ollama.correct,
      total = accuracy_cache.ollama.total,
      accuracy = accuracy_cache.ollama.total > 0 and (accuracy_cache.ollama.correct / accuracy_cache.ollama.total) or 0,
    },
    copilot = {
      correct = accuracy_cache.copilot.correct,
      total = accuracy_cache.copilot.total,
      accuracy = accuracy_cache.copilot.total > 0 and (accuracy_cache.copilot.correct / accuracy_cache.copilot.total) or 0,
    },
  }
end

function M.reset()
  accuracy_cache = {
    ollama = { correct = 0, total = 0 },
    copilot = { correct = 0, total = 0 },
  }
  M.save()
end

return M
