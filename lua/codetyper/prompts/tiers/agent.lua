--- Agent-tier prompt builder — for tool-capable models (Claude, GPT-4o, o3)
--- Supports multi-file operations: create files, move functions, add imports
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
You can create, modify, and organize files across the project.

REASONING: Think through the task carefully before producing code.
Start with @thinking, reason about the approach, then end thinking.

OUTPUT FORMAT — choose based on what the task requires:

**Single-file edit** (default): Output plain code that replaces/inserts at the selection.

**Multi-file operations** (refactor to new file, move function, reorganize):
Use these markers to specify file operations:

FILE:CREATE path/to/new/file.lua
```lua
<full new file content>
```

FILE:MODIFY path/to/existing/file.lua
<<<<<<< SEARCH
<exact existing code to find>
=======
<replacement code>
>>>>>>> REPLACE

FILE:DELETE path/to/file.lua

RULES for multi-file:
- FILE:CREATE writes a complete new file. Include all necessary requires/imports.
- FILE:MODIFY uses SEARCH/REPLACE. The SEARCH block must match EXACTLY.
- When moving a function to a new file, also FILE:MODIFY the original to:
  1. Add the require/import for the new module.
  2. Remove the moved function.
  3. Replace calls to the local function with the imported one.
- Use relative paths from the project root.
- You can chain multiple FILE: operations in one response.

When the user asks to "move", "extract", "refactor into", "split into", or
"create a new file" — use the multi-file format.
Otherwise, output plain code for single-file edits.
No markdown fences around single-file output. No explanations after the code.
]]
end

--- Build user prompt for agent tier
---@param event table
---@param ctx table
---@return string
local function build_user(event, ctx)
  local filename = vim.fn.fnamemodify(event.target_path or "", ":t")
  local rel_path = vim.fn.fnamemodify(event.target_path or "", ":~:.")
  local parts = {}

  table.insert(parts, string.format("File: %s (path: %s)", filename, rel_path))
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

  -- Project structure for context (helps the LLM choose good file paths)
  pcall(function()
    local utils = require("codetyper.support.utils")
    local root = utils.get_project_root()
    local tree_path = root .. "/.codetyper/tree.log"
    if vim.fn.filereadable(tree_path) == 1 then
      local tree_lines = vim.fn.readfile(tree_path)
      if tree_lines and #tree_lines > 0 then
        local tree_text = table.concat(tree_lines, "\n"):sub(1, 2000)
        table.insert(parts, "Project structure:")
        table.insert(parts, tree_text)
        table.insert(parts, "")
      end
    end
  end)

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
