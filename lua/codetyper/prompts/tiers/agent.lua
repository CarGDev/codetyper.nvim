--- Agent-tier prompt builder — for tool-capable models (Claude, GPT-4o, o3)
--- Allows reasoning, SEARCH/REPLACE blocks, richer context
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Build system prompt for agent-tier models
---@param event table
---@return string
local function build_system(event)
  local intent_mod = require("codetyper.core.intent")
  local base = ""
  if event.intent then
    base = intent_mod.get_prompt_modifier(event.intent)
  end

  return base .. [[

You are an expert coding assistant embedded in a Neovim editor.

REASONING: Think through the task carefully before producing code.
Start with @thinking, reason about the approach, then end thinking.

OUTPUT FORMAT: You may use SEARCH/REPLACE blocks for precise edits:
<<<<<<< SEARCH
exact code to find
=======
replacement code
>>>>>>> REPLACE

Or output plain code if replacing/inserting a region.
No markdown fences. No explanations after the code.
]]
end

--- Build user prompt for agent tier
---@param event table
---@param ctx table
---@return string
local function build_user(event, ctx)
  local filename = vim.fn.fnamemodify(event.target_path or "", ":t")
  local parts = {}

  table.insert(parts, string.format("File: %s (%s)", filename, ctx.filetype))
  table.insert(parts, "")

  -- Full file for context (use model's context limit)
  local limit = ctx.prompt_limit or 30000
  local file_content = ctx.target_content:sub(1, limit)
  table.insert(parts, string.format("```%s\n%s\n```", ctx.filetype, file_content))
  table.insert(parts, "")

  -- Scope info
  if event.scope and event.scope.type ~= "file" then
    table.insert(parts, string.format(
      "Cursor is inside %s \"%s\" (lines %d-%d).",
      event.scope.type,
      event.scope.name or "anonymous",
      event.scope.range and event.scope.range.start_row or 0,
      event.scope.range and event.scope.range.end_row or 0
    ))
  end

  -- Selection range
  if event.range then
    local action = event.intent and event.intent.action or "modify"
    table.insert(parts, string.format(
      "Selected lines %d-%d. Action: %s.",
      event.range.start_line, event.range.end_line or event.range.start_line,
      action
    ))
  end

  table.insert(parts, "")

  -- Extra context (brain, index, etc.)
  if ctx.extra and #ctx.extra > 0 then
    table.insert(parts, ctx.extra)
    table.insert(parts, "")
  end

  -- User request
  table.insert(parts, "User request: " .. (event.prompt_content or ""))

  return table.concat(parts, "\n")
end

--- Main entry point
---@param event table PromptEvent
---@param ctx table Context from build_context.gather()
---@return string user_prompt
---@return string system_prompt
function M.build_prompt(event, ctx)
  local system_prompt = build_system(event)
  local user_prompt = build_user(event, ctx)

  flog.info("tier.agent", string.format("prompt_len=%d system_len=%d", #user_prompt, #system_prompt)) -- TODO: remove after debugging

  return user_prompt, system_prompt
end

return M
