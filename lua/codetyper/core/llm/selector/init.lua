--- Selector — wires select + ponder + accuracy for smart provider selection
local M = {}

local select_provider = require("codetyper.core.llm.selector.select")
local ponder_mod = require("codetyper.core.llm.selector.ponder")
local accuracy = require("codetyper.core.llm.selector.accuracy")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

M.select_provider = select_provider
M.should_ponder = ponder_mod.should_ponder
M.ponder = ponder_mod.ponder
M.get_accuracy_stats = accuracy.get_stats
M.reset_accuracy_stats = accuracy.reset
M.report_feedback = accuracy.record

--- Smart generate with automatic provider selection and pondering
---@param prompt string
---@param context table
---@param callback fun(response: string|nil, error: string|nil, metadata: table|nil)
function M.smart_generate(prompt, context, callback)
  local selection = select_provider(prompt, context)

  flog.info("selector", string.format( -- TODO: remove after debugging
    "provider=%s confidence=%.0f%% memories=%d reason=%s",
    selection.provider, selection.confidence * 100, selection.memory_count, selection.reason
  ))

  pcall(function()
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
      type = "info",
      message = string.format("LLM: %s (%.0f%%, %s)", selection.provider, selection.confidence * 100, selection.reason),
    })
  end)

  local client
  if selection.provider == "ollama" then
    client = require("codetyper.core.llm.providers.ollama")
  else
    client = require("codetyper.core.llm.providers.copilot")
  end

  client.generate(prompt, context, function(response, err)
    if err then
      if selection.provider == "ollama" then
        local copilot = require("codetyper.core.llm.providers.copilot")
        copilot.generate(prompt, context, function(fb_response, fb_err)
          callback(fb_response, fb_err, {
            provider = "copilot",
            fallback = true,
            original_provider = "ollama",
            original_error = err,
          })
        end)
        return
      end
      callback(nil, err, { provider = selection.provider })
      return
    end

    if selection.provider == "ollama" and ponder_mod.should_ponder(selection.confidence) then
      ponder_mod.ponder(prompt, context, response, function(result)
        if result.ollama_correct then
          callback(response, nil, {
            provider = "ollama",
            pondered = true,
            agreement = result.agreement_score,
            confidence = selection.confidence,
          })
        else
          callback(result.verifier_response, nil, {
            provider = "copilot",
            pondered = true,
            agreement = result.agreement_score,
            original_provider = "ollama",
            corrected = true,
          })
        end
      end)
    else
      callback(response, nil, {
        provider = selection.provider,
        pondered = false,
        confidence = selection.confidence,
      })
    end
  end)
end

return M
