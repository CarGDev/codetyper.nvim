--- Parse agent-style LLM responses into file operations
--- Format the LLM is instructed to use:
---
--- FILE:CREATE path/to/new/file.lua
--- ```lua
--- <new file content>
--- ```
---
--- FILE:MODIFY path/to/existing/file.lua
--- <<<<<<< SEARCH
--- <exact code to find>
--- =======
--- <replacement code>
--- >>>>>>> REPLACE
---
--- FILE:DELETE path/to/file.lua

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

---@class FileOperation
---@field action "create"|"modify"|"delete"
---@field path string File path (relative to project root)
---@field content string|nil New file content (for create)
---@field search string|nil Code to find (for modify)
---@field replace string|nil Replacement code (for modify)

--- Parse a structured agent response into file operations
---@param response string Raw LLM response
---@param project_root string Project root path
---@return FileOperation[] operations
---@return boolean is_agent_response Whether the response contained agent operations
local function parse_response(response, project_root)
  local ops = {}

  -- Strip thinking block first
  local cleaned = response:gsub("@thinking.-end thinking\n?", "")

  -- Check if this looks like an agent response (has FILE: markers)
  if not cleaned:match("FILE:") then
    return ops, false
  end

  flog.info("agent.parse", "detected agent response format") -- TODO: remove after debugging

  -- Parse FILE:CREATE blocks
  for path, content in cleaned:gmatch("FILE:CREATE%s+([^\n]+)\n```[^\n]*\n(.-)\n```") do
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    -- Resolve relative path
    local full_path = path
    if not path:match("^/") then
      full_path = project_root .. "/" .. path
    end
    table.insert(ops, {
      action = "create",
      path = full_path,
      content = content,
    })
    flog.info("agent.parse", "CREATE: " .. full_path) -- TODO: remove after debugging
  end

  -- Parse FILE:MODIFY blocks with SEARCH/REPLACE
  for path, block in cleaned:gmatch("FILE:MODIFY%s+([^\n]+)\n(<<<<<<< SEARCH.->>>>>>> REPLACE)") do
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    local full_path = path
    if not path:match("^/") then
      full_path = project_root .. "/" .. path
    end

    -- Extract search and replace from the block
    local search = block:match("<<<<<<< SEARCH\n(.-)\n=======")
    local replace_text = block:match("=======\n(.-)\n>>>>>>> REPLACE")

    if search and replace_text then
      table.insert(ops, {
        action = "modify",
        path = full_path,
        search = search,
        replace = replace_text,
      })
      flog.info("agent.parse", "MODIFY: " .. full_path) -- TODO: remove after debugging
    end
  end

  -- Parse FILE:DELETE
  for path in cleaned:gmatch("FILE:DELETE%s+([^\n]+)") do
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    local full_path = path
    if not path:match("^/") then
      full_path = project_root .. "/" .. path
    end
    table.insert(ops, {
      action = "delete",
      path = full_path,
    })
    flog.info("agent.parse", "DELETE: " .. full_path) -- TODO: remove after debugging
  end

  flog.info("agent.parse", string.format("parsed %d operations", #ops)) -- TODO: remove after debugging

  return ops, #ops > 0
end

return parse_response
