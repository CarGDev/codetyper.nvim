--- Parse agent-style LLM responses into file operations
--- Handles both fenced and unfenced content blocks.

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

---@class FileOperation
---@field action "create"|"modify"|"delete"
---@field path string File path (absolute)
---@field content string|nil New file content (for create)
---@field search string|nil Code to find (for modify)
---@field replace string|nil Replacement code (for modify)

--- Resolve a path relative to project root
---@param path string
---@param project_root string
---@return string absolute path
local function resolve_path(path, project_root)
  path = path:gsub("^%s+", ""):gsub("%s+$", "")
  if path:match("^/") then
    return path
  end
  return project_root .. "/" .. path
end

--- Split response into sections by FILE: markers
---@param text string
---@return table[] sections { marker, path, body }
local function split_sections(text)
  local sections = {}
  -- Match FILE:ACTION path\n then capture everything until the next FILE: or end
  local pattern = "(FILE:%w+)%s+([^\n]+)\n"
  local last_end = 1

  -- Find all FILE: markers and their positions
  local markers = {}
  local search_start = 1
  while true do
    local m_start, m_end, action, path = text:find(pattern, search_start)
    if not m_start then
      break
    end
    table.insert(markers, { start = m_start, body_start = m_end + 1, action = action, path = path })
    search_start = m_end + 1
  end

  -- Extract body for each marker (everything between this marker and the next)
  for i, m in ipairs(markers) do
    local body_end
    if markers[i + 1] then
      body_end = markers[i + 1].start - 1
    else
      body_end = #text
    end
    local body = text:sub(m.body_start, body_end):gsub("%s+$", "")
    table.insert(sections, {
      action = m.action,
      path = m.path,
      body = body,
    })
  end

  return sections
end

--- Strip code fences from content if present
---@param body string
---@return string cleaned content
local function strip_fences(body)
  -- Remove opening fence: ```lua or ```
  local content = body:gsub("^```[^\n]*\n", "")
  -- Remove closing fence
  content = content:gsub("\n```%s*$", "")
  content = content:gsub("^```%s*$", "")
  return content
end

--- Parse a structured agent response into file operations
---@param response string Raw LLM response
---@param project_root string Project root path
---@return FileOperation[] operations
---@return boolean is_agent_response
local function parse_response(response, project_root)
  local ops = {}

  -- Strip thinking block
  local cleaned = response:gsub("@thinking.-end thinking\n?", "")

  if not cleaned:match("FILE:") then
    return ops, false
  end

  flog.info("agent.parse", "detected agent response format") -- TODO: remove after debugging

  local sections = split_sections(cleaned)

  for _, section in ipairs(sections) do
    local full_path = resolve_path(section.path, project_root)

    if section.action == "FILE:CREATE" then
      local content = strip_fences(section.body)
      table.insert(ops, {
        action = "create",
        path = full_path,
        content = content,
      })
      flog.info("agent.parse", "CREATE: " .. full_path) -- TODO: remove after debugging

    elseif section.action == "FILE:MODIFY" then
      -- Extract SEARCH/REPLACE blocks from the body
      local body = section.body
      local search_start = 1
      while true do
        local s_start = body:find("<<<<<<< SEARCH\n", search_start)
        if not s_start then
          break
        end
        local sep = body:find("\n=======\n", s_start)
        local r_end = body:find("\n>>>>>>> REPLACE", sep or s_start)

        if sep and r_end then
          local search = body:sub(s_start + #"<<<<<<< SEARCH\n", sep - 1)
          local replace_text = body:sub(sep + #"\n=======\n", r_end - 1)

          table.insert(ops, {
            action = "modify",
            path = full_path,
            search = search,
            replace = replace_text,
          })
          flog.info("agent.parse", "MODIFY: " .. full_path) -- TODO: remove after debugging
          search_start = r_end + 1
        else
          break
        end
      end

    elseif section.action == "FILE:DELETE" then
      table.insert(ops, {
        action = "delete",
        path = full_path,
      })
      flog.info("agent.parse", "DELETE: " .. full_path) -- TODO: remove after debugging
    end
  end

  flog.info("agent.parse", string.format("parsed %d operations", #ops)) -- TODO: remove after debugging

  return ops, #ops > 0
end

return parse_response
