--- Tier router — selects prompt builder based on model capability
local M = {}

local model_tiers = require("codetyper.constants.model_tiers")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Build prompt using the appropriate tier strategy for the model
---@param model string Model name (e.g. "gpt-4o-mini", "claude-3.5-sonnet")
---@param event table PromptEvent
---@param ctx table Context from build_context.gather()
---@return string user_prompt
---@return string system_prompt
function M.build_prompt(model, event, ctx)
  local model_caps = require("codetyper.constants.model_caps")
  local actual_model = model or "copilot"
  local tier = model_tiers.get_tier(actual_model)
  local prompt_limit = model_caps.get_prompt_limit(actual_model)

  -- Attach prompt limit to context so tier builders can use it
  ctx.prompt_limit = prompt_limit

  flog.info("tier_router", string.format( -- TODO: remove after debugging
    "model=%s tier=%s prompt_limit=%d", actual_model, tier, prompt_limit
  ))

  local builder = require("codetyper.prompts.tiers." .. tier)
  return builder.build_prompt(event, ctx)
end

return M
