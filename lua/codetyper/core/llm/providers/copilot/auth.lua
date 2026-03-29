--- Copilot OAuth token discovery and GitHub token refresh
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging
local http = require("codetyper.core.llm.shared.http")

local AUTH_URL = "https://api.github.com/copilot_internal/v2/token"

--- Cached state (singleton per session)
M.state = nil

--- Discover OAuth token from copilot.lua or copilot.vim config files
---@return string|nil OAuth token
function M.discover_oauth_token()
  local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
  local os_name = vim.loop.os_uname().sysname:lower()

  local config_dir
  if xdg_config and vim.fn.isdirectory(xdg_config) > 0 then
    config_dir = xdg_config
  elseif os_name:match("linux") or os_name:match("darwin") then
    config_dir = vim.fn.expand("~/.config")
  else
    config_dir = vim.fn.expand("~/AppData/Local")
  end

  local paths = { "hosts.json", "apps.json" }
  for _, filename in ipairs(paths) do
    local path = config_dir .. "/github-copilot/" .. filename
    if vim.fn.filereadable(path) == 1 then
      local content = vim.fn.readfile(path)
      if content and #content > 0 then
        local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
        if ok and data then
          for key, value in pairs(data) do
            if key:match("github.com") and value.oauth_token then
              flog.info("copilot.auth", "found OAuth token from " .. filename) -- TODO: remove after debugging
              return value.oauth_token
            end
          end
        end
      end
    end
  end

  return nil
end

--- Initialize state if needed
function M.ensure_initialized()
  if not M.state then
    M.state = {
      oauth_token = M.discover_oauth_token(),
      github_token = nil,
    }
  end
end

--- Refresh GitHub API token using OAuth token
---@param callback fun(token: table|nil, error: string|nil)
function M.refresh_github_token(callback)
  M.ensure_initialized()

  if not M.state or not M.state.oauth_token then
    callback(nil, "No OAuth token available")
    return
  end

  -- Check if current token is still valid
  if M.state.github_token and M.state.github_token.expires_at then
    if M.state.github_token.expires_at > os.time() then
      callback(M.state.github_token, nil)
      return
    end
  end

  local headers = {
    "Authorization: token " .. M.state.oauth_token,
    "Accept: application/json",
  }

  http.get(AUTH_URL, headers, function(parsed, err)
    if err then
      callback(nil, "Token refresh failed: " .. err)
      return
    end

    if parsed.error then
      callback(nil, parsed.error_description or "Token refresh failed")
      return
    end

    M.state.github_token = parsed
    flog.info("copilot.auth", "token refreshed successfully") -- TODO: remove after debugging
    callback(parsed, nil)
  end)
end

--- Get a valid GitHub token (refreshes if expired)
---@param callback fun(token: table|nil, error: string|nil)
function M.get_valid_token(callback)
  M.refresh_github_token(callback)
end

--- Check if authenticated
---@return boolean
function M.is_authenticated()
  M.ensure_initialized()
  return M.state ~= nil and M.state.oauth_token ~= nil
end

return M
