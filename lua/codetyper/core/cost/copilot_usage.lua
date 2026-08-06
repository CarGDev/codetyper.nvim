--- Live Copilot account usage (premium request credits) for the cost window.
local M = {}

--- Get Copilot account quota/usage.
---@param callback fun(quota: table|nil, err: string|nil)
function M.get_usage(callback)
  local ok, auth = pcall(require, "codetyper.core.llm.providers.copilot.auth")
  if not ok then
    callback(nil, "Copilot auth module unavailable")
    return
  end
  auth.get_quota(callback)
end

return M
