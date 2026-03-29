--- Chat-tier prompt builder — for models that follow instructions but need strict guardrails
--- Used by: Copilot (GPT-4o-mini), Ollama large models, Claude Haiku
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Build system prompt with thinking format
---@param event table PromptEvent
---@return string system_prompt
local function build_system(event)
  local intent_mod = require("codetyper.core.intent")
  local base = ""
  if event.intent then
    base = intent_mod.get_prompt_modifier(event.intent)
  end

  return base .. [[

OUTPUT FORMAT:
1. Start with exactly: @thinking
2. Brief reasoning (1-3 lines max).
3. End with exactly: end thinking
4. Then output ONLY code. No markdown fences, no explanations, no comments about what you did.

CRITICAL RULES:
- Output ONLY the code that should be inserted or that replaces the selection.
- Do NOT repeat surrounding code that already exists in the file.
- Do NOT wrap output in ```code fences```.
- Do NOT add explanations before or after the code.
- Preserve the exact indentation style of the surrounding code.
]]
end

--- Build prompt for inline tagged prompts (/@ ... @/)
---@param event table
---@param ctx table Context from build_context
---@return string prompt
local function build_inline(event, ctx)
  local start_line = event.range.start_line
  local end_line = event.range.end_line or start_line
  local limit = ctx.prompt_limit or 12000
  local file_content = table.concat(ctx.target_lines, "\n"):sub(1, limit)
  local filename = vim.fn.fnamemodify(event.target_path or "", ":t")

  return string.format(
    [[You are editing a %s file: %s

TASK: %s
%s
FULL FILE:
```%s
%s
```

You are REPLACING lines %d-%d. Output ONLY the replacement code for those lines.
Do NOT include any code outside that range. Preserve indentation.]],
    ctx.filetype, filename,
    event.prompt_content,
    ctx.extra,
    ctx.filetype, file_content,
    start_line, end_line
  )
end

--- Build prompt for scoped code (inside a function/method/class)
---@param event table
---@param ctx table
---@return string prompt
local function build_scoped(event, ctx)
  local intent_mod = require("codetyper.core.intent")
  local scope_type = event.scope.type
  local scope_name = event.scope.name or "anonymous"
  local scope_text = event.scope_text

  -- "complete" intent — fill in the function body
  if event.intent and event.intent.type == "complete" then
    return string.format(
      [[Complete this %s. Fill in the implementation.

RULES:
- Keep the EXACT same function signature (name, parameters, return type).
- Return ONLY the complete %s with implementation.
- Do NOT duplicate the signature or create a new function.

Current %s (incomplete):
```%s
%s
```
%s
What it should do: %s]],
      scope_type,
      scope_type,
      scope_type,
      ctx.filetype, scope_text,
      ctx.extra,
      event.prompt_content
    )
  end

  -- Replacement intent — transform the scope
  if event.intent and intent_mod.is_replacement(event.intent) then
    local line_count = 0
    if event.range then
      line_count = (event.range.end_line or event.range.start_line) - event.range.start_line + 1
    end

    return string.format(
      [[You are editing a %s named "%s" in a %s file.

SELECTED CODE (lines %d-%d, %d lines):
```%s
%s
```
%s
User request: %s

RULES:
- Replace ONLY the selected code above.
- Your output must be roughly %d lines (the same region).
- Do NOT include code from outside the selection.
- Do NOT add surrounding function declarations or closing ends unless they were in the selection.
- Output ONLY the replacement code.]],
      scope_type, scope_name, ctx.filetype,
      event.range and event.range.start_line or 0,
      event.range and event.range.end_line or 0,
      line_count,
      ctx.filetype, scope_text,
      ctx.extra,
      event.prompt_content,
      line_count
    )
  end

  -- Insertion intent — add code within scope
  return string.format(
    [[You are inside %s "%s" in a %s file. Insert code at line %d.

Enclosing %s:
```%s
%s
```
%s
User request: %s

Output ONLY the new code to insert. Do NOT repeat existing code from the function above.]],
    scope_type, scope_name, ctx.filetype,
    event.range and event.range.start_line or 0,
    scope_type,
    ctx.filetype, scope_text,
    ctx.extra,
    event.prompt_content
  )
end

--- Build prompt for full-file context (no scope resolved)
---@param event table
---@param ctx table
---@return string prompt
local function build_file(event, ctx)
  local filename = vim.fn.fnamemodify(event.target_path or "", ":t")

  return string.format(
    [[File: %s (%s)

```%s
%s
```
%s
User request: %s

Output ONLY the code. No explanations.]],
    filename, ctx.filetype,
    ctx.filetype, ctx.target_content:sub(1, ctx.prompt_limit or 8000),
    ctx.extra,
    event.prompt_content
  )
end

--- Main entry point — build prompt for chat-tier model
---@param event table PromptEvent
---@param ctx table Context from build_context.gather()
---@return string user_prompt
---@return string system_prompt
function M.build_prompt(event, ctx)
  local system_prompt = build_system(event)
  local user_prompt

  -- Inline tagged prompt (/@ ... @/)
  local is_inline = event.target_path
    and not (event.target_path):match("%.codetyper%.")
    and event.range and event.range.start_line

  if is_inline and event.scope_text and event.scope and event.scope.type ~= "file" then
    user_prompt = build_scoped(event, ctx)
  elseif is_inline then
    user_prompt = build_inline(event, ctx)
  elseif event.scope_text and event.scope and event.scope.type ~= "file" then
    user_prompt = build_scoped(event, ctx)
  else
    user_prompt = build_file(event, ctx)
  end

  flog.info("tier.chat", string.format("prompt_len=%d system_len=%d", #user_prompt, #system_prompt)) -- TODO: remove after debugging

  return user_prompt, system_prompt
end

return M
