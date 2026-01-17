---@class PermissionResult
---@field allowed boolean Whether the tool execution is allowed
---@field auto boolean Whether this was auto-approved
---@field reason string Reason for the decision

local M = {}
local session = require("codetyper.features.agents.middleware.session")

---Tools that are safe and auto-approve (read-only operations)
local SAFE_TOOLS = {
  view = true,
  read = true,
  read_file = true,
  grep = true,
  glob = true,
  list = true,
  show = true,
  get = true,
  search = true,
  find = true,
  find_files = true,
  list_files = true,
  cat = true,
  file_read = true,
  get_file = true,
}

---Dangerous patterns in bash commands that require approval
local DANGEROUS_PATTERNS = {
  "rm%s+%-rf",
  "rm%s+%-fr",
  "sudo",
  "dd%s+",
  "mkfs",
  ":%s*!",  -- Vim shell commands
  ">%s*/dev/",
  "curl.*|.*sh",
  "wget.*|.*sh",
  "chmod%s+777",
  "chown%s+%-R",
}

---Create a cache key for a tool call
---@param tool_name string
---@param input table
---@return string
local function make_cache_key(tool_name, input)
  -- For bash commands, cache by command pattern
  if tool_name == "bash" and input.command then
    -- Normalize command for caching (remove variable parts)
    local cmd = input.command:gsub("%d+", "N"):gsub("%s+", " ")
    return tool_name .. ":" .. cmd
  end

  -- For other tools, cache by full input
  return tool_name .. ":" .. vim.inspect(input)
end

---Check if a bash command contains dangerous patterns
---@param command string
---@return boolean is_dangerous
---@return string? pattern The matched dangerous pattern
local function is_dangerous_bash(command)
  for _, pattern in ipairs(DANGEROUS_PATTERNS) do
    if command:match(pattern) then
      return true, pattern
    end
  end
  return false
end

---Check if a tool execution requires permission
---@param tool_name string The name of the tool
---@param input table The tool input parameters
---@param opts? table Additional options
---@return PermissionResult
function M.check(tool_name, input, opts)
  opts = opts or {}

  -- Auto-approve safe read-only tools
  if SAFE_TOOLS[tool_name] then
    return {
      allowed = true,
      auto = true,
      reason = "Read-only operation",
    }
  end

  -- Check session cache
  local sess = session.get_current()
  if sess then
    local cache_key = make_cache_key(tool_name, input)
    if sess.permissions[cache_key] then
      return {
        allowed = true,
        auto = true,
        reason = "Previously approved in session",
      }
    end
  end

  -- Special handling for bash commands
  if tool_name == "bash" then
    local cmd = input.command
    if not cmd then
      return {
        allowed = false,
        auto = false,
        reason = "Missing command",
      }
    end

    local is_dangerous, pattern = is_dangerous_bash(cmd)
    if is_dangerous then
      return {
        allowed = false,
        auto = false,
        reason = string.format("Dangerous command pattern: %s", pattern),
      }
    end

    -- Non-dangerous bash commands still need approval by default
    return {
      allowed = false,
      auto = false,
      reason = "Bash command requires approval",
    }
  end

  -- Write operations need approval
  if tool_name:match("write") or tool_name:match("edit") or tool_name:match("delete") then
    return {
      allowed = false,
      auto = false,
      reason = "Write operation requires approval",
    }
  end

  -- Default: require approval for unknown tools
  return {
    allowed = false,
    auto = false,
    reason = "Unknown tool requires approval",
  }
end

---Grant permission for a tool execution
---@param tool_name string
---@param input table
---@param level? string "session" | "permanent" (default: session)
function M.grant(tool_name, input, level)
  level = level or "session"

  if level == "session" then
    local sess = session.get_current()
    if sess then
      local cache_key = make_cache_key(tool_name, input)
      sess.permissions[cache_key] = true
    end
  elseif level == "permanent" then
    -- TODO: Implement permanent permissions (stored in config)
    -- For now, just use session level
    M.grant(tool_name, input, "session")
  end
end

---Revoke a previously granted permission
---@param tool_name string
---@param input table
function M.revoke(tool_name, input)
  local sess = session.get_current()
  if sess then
    local cache_key = make_cache_key(tool_name, input)
    sess.permissions[cache_key] = nil
  end
end

---Clear all permissions in current session
function M.clear_session()
  local sess = session.get_current()
  if sess then
    sess.permissions = {}
  end
end

---Add a custom safe tool
---@param tool_name string
function M.register_safe_tool(tool_name)
  SAFE_TOOLS[tool_name] = true
end

---Add a custom dangerous pattern for bash commands
---@param pattern string Lua pattern to match
function M.register_dangerous_pattern(pattern)
  table.insert(DANGEROUS_PATTERNS, pattern)
end

return M
