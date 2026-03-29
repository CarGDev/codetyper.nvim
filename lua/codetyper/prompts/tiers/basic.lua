--- Basic-tier prompt builder — for code-completion-only models (codellama, small Ollama)
--- Minimal prompt, fill-in-the-middle style, no system prompt overhead
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Main entry point
---@param event table PromptEvent
---@param ctx table Context from build_context.gather()
---@return string user_prompt
---@return string system_prompt (empty for basic tier)
function M.build_prompt(event, ctx)
  local lines = ctx.target_lines
  local start_line = event.range and event.range.start_line or 1
  local end_line = event.range and event.range.end_line or start_line

  -- Show lines around the cursor for context (fill-in-the-middle style)
  local context_before = {}
  local context_after = {}
  local window = 30

  for i = math.max(1, start_line - window), start_line - 1 do
    if lines[i] then
      table.insert(context_before, lines[i])
    end
  end

  for i = end_line + 1, math.min(#lines, end_line + window) do
    if lines[i] then
      table.insert(context_after, lines[i])
    end
  end

  local user_prompt = string.format(
    "%s\n-- %s\n%s",
    table.concat(context_before, "\n"),
    event.prompt_content or "complete this",
    table.concat(context_after, "\n")
  )

  flog.info("tier.basic", string.format("prompt_len=%d", #user_prompt)) -- TODO: remove after debugging

  -- No system prompt for basic models — keep it lean
  return user_prompt, ""
end

return M
