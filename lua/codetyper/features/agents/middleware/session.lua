---@class AgentSession
---@field id string Unique session identifier
---@field permissions table<string, boolean> Cached permissions for this session
---@field created_at number Session creation timestamp
---@field context table Additional session context

local M = {}

---@type AgentSession|nil
local current_session = nil

---Create a new agent session
---@param opts? table Optional session options
---@return AgentSession
function M.create(opts)
  opts = opts or {}

  current_session = {
    id = opts.id or tostring(os.time()) .. "-" .. math.random(1000, 9999),
    permissions = {},
    created_at = os.time(),
    context = opts.context or {},
  }

  return current_session
end

---Get the current active session
---@return AgentSession|nil
function M.get_current()
  return current_session
end

---Clear the current session
function M.clear()
  current_session = nil
end

---Check if a session is active
---@return boolean
function M.is_active()
  return current_session ~= nil
end

---Get session age in seconds
---@return number|nil
function M.get_age()
  if not current_session then
    return nil
  end
  return os.time() - current_session.created_at
end

---Store arbitrary data in session context
---@param key string
---@param value any
function M.set_context(key, value)
  if current_session then
    current_session.context[key] = value
  end
end

---Retrieve data from session context
---@param key string
---@return any
function M.get_context(key)
  if not current_session then
    return nil
  end
  return current_session.context[key]
end

return M
