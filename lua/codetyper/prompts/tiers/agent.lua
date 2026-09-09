--- Agent-tier prompt builder — for tool-capable models (Claude, GPT-4o, o3)
--- Supports multi-file operations: create files, move functions, add imports
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local TOOL_MARKERS = {
  codegraph_context = "TOOL:CODEGRAPH",
  tokensave_search = "TOOL:TOKENSAVE",
  context7_resolve_library = "TOOL:CONTEXT7_RESOLVE",
  context7_query_docs = "TOOL:CONTEXT7_QUERY",
  ask_user = "TOOL:ASK_USER",
  add_import = "TOOL:ADD_IMPORT",
}

local TOOL_DESCRIPTIONS = {
  codegraph_context = "Read bounded local project context.",
  tokensave_search = "Search a current local project index.",
  context7_resolve_library = "Resolve a library through read-only Context7.",
  context7_query_docs = "Query read-only Context7 documentation.",
  ask_user = "Ask the user one bounded selectable question.",
  add_import = "Add one safe, single-line import declaration.",
}

local TOOL_LIMITS = {
  codegraph_context = "query <= 2000 chars; max_nodes 1..100; no_code boolean",
  tokensave_search = "query <= 2000 chars; limit 1..100",
  context7_resolve_library = "query <= 1000 chars",
  context7_query_docs = "library_id <= 200 chars; query <= 2000 chars",
  ask_user = "question <= 1000 chars; options 1..8, each <= 200 chars",
  add_import = "path <= 1000 chars; statement <= 500 chars and single-line",
}

local function available_tools(capabilities)
  if type(capabilities) ~= "table" then
    return {}
  end

  local source = capabilities.available_tools
  if type(source) ~= "table" then
    source = capabilities.tools
  end
  if type(source) ~= "table" then
    return {}
  end

  local result, seen = {}, {}
  for _, tool in ipairs(source) do
    if type(tool) == "table" and type(tool.name) == "string" and TOOL_MARKERS[tool.name] and not seen[tool.name] then
      local is_available = tool.available == true or tool.status == "available"
      if is_available and tool.stale ~= true then
        seen[tool.name] = true
        result[#result + 1] = tool.name
      end
    end
  end
  table.sort(result)
  return result
end

local function build_capability_instructions(capabilities)
  local names = available_tools(capabilities)
  if #names == 0 then
    return ""
  end

  local native = type(capabilities) == "table" and capabilities.native_tools == true
  local markers = type(capabilities) == "table" and capabilities.marker_tools == true
  if not native and not markers then
    return ""
  end

  local parts = {
    "\n\n--- CAPABILITY-BOUND TOOLS ---",
    "Advertise and use only the explicitly available schemas below.",
    "Results use {status,data,error,stale} and are bounded to 4000 characters.",
    "Unavailable, stale, or invalid tools must not be claimed or called.",
    "External work is performed only after an explicit model tool call; prompt construction never invokes tools.",
  }

  if native then
    parts[#parts + 1] = "Native structured schemas: enabled for this eligible Copilot project task."
  else
    parts[#parts + 1] = "Native structured schemas: unavailable for this request."
  end
  if markers then
    parts[#parts + 1] = "Text-marker fallback: enabled; use the marker shown for each available tool."
  else
    parts[#parts + 1] = "Text-marker fallback: unavailable for this request."
  end

  for _, name in ipairs(names) do
    local modes = {}
    if native then
      modes[#modes + 1] = "native schema"
    end
    if markers then
      modes[#modes + 1] = TOOL_MARKERS[name]
    end
    parts[#parts + 1] = string.format(
      "- %s [%s] (%s): %s",
      name,
      table.concat(modes, ", "),
      TOOL_LIMITS[name],
      TOOL_DESCRIPTIONS[name]
    )
  end

  return table.concat(parts, "\n")
end

--- Build system prompt for agent-tier models
---@param event table
---@return string
local function build_system(event, capabilities)
  local intent_mod = require("codetyper.core.intent")
  local base = ""
  if event.intent then
    base = intent_mod.get_prompt_modifier(event.intent)
  end

  base = base .. [[

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

**Tool calls** (when you need information or to run commands):

TOOL:TERMINAL <shell command>
  Runs a shell command and returns output. Use for: listing files, checking
  dependencies, reading file contents, running tests, grep/search.

TOOL:MCP <server>/<tool> {"arg": "value"}
  Calls an MCP tool from an available server. Use for specialized operations.

You can mix FILE: operations and TOOL: calls in the same response.
Tool results will be shown to the user.
]]

  base = base .. build_capability_instructions(capabilities)

  return base
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

  -- Selection/tag range
  if event.range then
    local start_l = event.range.start_line
    local end_l = event.range.end_line or start_l
    local action = event.intent and event.intent.action or "modify"

    -- Tag-originated prompt (no intent_override): the tag lines will be replaced
    if not event.intent_override then
      table.insert(parts, string.format(
        "Lines %d-%d contain a /@ @/ prompt tag. Your output will REPLACE those exact lines.",
        start_l, end_l
      ))
      table.insert(parts, "Output ONLY the code to insert at that location. Do NOT use FILE:MODIFY for this.")
      table.insert(parts, "Do NOT output the /@ @/ tags themselves.")
    else
      table.insert(parts, string.format(
        "Selected lines %d-%d. Action: %s.",
        start_l, end_l, action
      ))
    end
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
  local system_prompt = build_system(event, ctx and ctx.tool_capabilities or event.tool_capabilities)
  local user_prompt = build_user(event, ctx)

  flog.info("tier.agent", string.format("prompt_len=%d system_len=%d", #user_prompt, #system_prompt)) -- TODO: remove after debugging

  return user_prompt, system_prompt
end

M.build_capability_instructions = build_capability_instructions

return M
