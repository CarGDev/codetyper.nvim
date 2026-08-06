--- GitHub Device Flow authentication for Copilot.
--- Lets users connect Codetyper to GitHub Copilot without needing
--- copilot.vim/copilot.lua installed — implements the same OAuth Device Flow
--- those plugins use, and writes the token to the same hosts.json location
--- so it stays interoperable.
local M = {}

local http = require("codetyper.core.llm.shared.http")
local utils = require("codetyper.support.utils")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

-- Standard GitHub OAuth client_id used by copilot.vim / copilot.lua (public,
-- well-known client id for the Device Flow — not a secret).
local CLIENT_ID = "Iv1.b507a08c87ecfe98"
local DEVICE_CODE_URL = "https://github.com/login/device/code"
local ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token"

--- Path where copilot.vim/copilot.lua store the oauth token, so writing here
--- keeps us interoperable with those plugins.
---@return string
local function hosts_json_path()
  local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
  local config_dir
  if xdg_config and xdg_config ~= "" and vim.fn.isdirectory(xdg_config) > 0 then
    config_dir = xdg_config
  else
    local os_name = vim.loop.os_uname().sysname:lower()
    if os_name:match("linux") or os_name:match("darwin") then
      config_dir = vim.fn.expand("~/.config")
    else
      config_dir = vim.fn.expand("~/AppData/Local")
    end
  end
  return config_dir .. "/github-copilot/hosts.json"
end

--- Persist the oauth token to hosts.json (merges with any existing entries)
---@param oauth_token string
local function save_oauth_token(oauth_token)
  local path = hosts_json_path()
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  local data = {}
  if vim.fn.filereadable(path) == 1 then
    local content = table.concat(vim.fn.readfile(path), "\n")
    local ok, parsed = pcall(vim.json.decode, content)
    if ok and type(parsed) == "table" then
      data = parsed
    end
  end

  data["github.com"] = data["github.com"] or {}
  data["github.com"].oauth_token = oauth_token
  data["github.com"].user = data["github.com"].user or "codetyper"

  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    return false
  end

  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(json)
  f:close()
  return true
end

--- Poll the access_token endpoint until the user completes the browser flow
---@param device_code string
---@param interval number seconds between polls
---@param expires_at number os.time() deadline
---@param on_done fun(oauth_token: string|nil, err: string|nil)
local function poll_for_token(device_code, interval, expires_at, on_done)
  if os.time() > expires_at then
    on_done(nil, "Device code expired. Run :Coder auth to try again.")
    return
  end

  vim.defer_fn(function()
    local body = vim.json.encode({
      client_id = CLIENT_ID,
      device_code = device_code,
      grant_type = "urn:ietf:params:oauth:grant-type:device_code",
    })

    http.post(ACCESS_TOKEN_URL, { "Accept: application/json", "Content-Type: application/json" }, body, function(parsed, err)
      if err then
        on_done(nil, "Auth polling failed: " .. err)
        return
      end

      if parsed.access_token then
        on_done(parsed.access_token, nil)
        return
      end

      local error_code = parsed.error
      if error_code == "authorization_pending" then
        poll_for_token(device_code, interval, expires_at, on_done)
      elseif error_code == "slow_down" then
        poll_for_token(device_code, interval + 5, expires_at, on_done)
      elseif error_code == "expired_token" then
        on_done(nil, "Device code expired. Run :Coder auth to try again.")
      elseif error_code == "access_denied" then
        on_done(nil, "Authorization was denied.")
      else
        on_done(nil, parsed.error_description or error_code or "Unknown error during authorization")
      end
    end)
  end, interval * 1000)
end

--- Start the GitHub Device Flow: requests a device/user code, shows it to the
--- user, opens the verification URL, and polls until authorized.
---@param callback fun(success: boolean, err: string|nil)
function M.start(callback)
  local body = vim.json.encode({ client_id = CLIENT_ID, scope = "read:user" })

  utils.notify("Connecting to GitHub Copilot...", vim.log.levels.INFO)

  http.post(DEVICE_CODE_URL, { "Accept: application/json", "Content-Type: application/json" }, body, function(parsed, err)
    if err then
      callback(false, "Failed to start device flow: " .. err)
      return
    end

    if not parsed or not parsed.device_code then
      callback(false, "Unexpected response from GitHub while starting device flow")
      return
    end

    local user_code = parsed.user_code
    local verification_uri = parsed.verification_uri
    local expires_at = os.time() + (parsed.expires_in or 900)
    local interval = parsed.interval or 5

    -- Try to open the verification URL in the browser
    pcall(function()
      vim.ui.open(verification_uri)
    end)

    utils.notify(
      string.format(
        "GitHub Copilot authentication:\n\n  1. Open: %s\n  2. Enter code: %s\n\nWaiting for you to authorize...",
        verification_uri,
        user_code
      ),
      vim.log.levels.INFO
    )

    flog.info("copilot.device_auth", "device flow started, user_code=" .. user_code)

    poll_for_token(parsed.device_code, interval, expires_at, function(oauth_token, poll_err)
      if poll_err then
        callback(false, poll_err)
        return
      end

      save_oauth_token(oauth_token)

      -- Update the live auth module state immediately so we don't require
      -- a restart to start using Copilot.
      local ok_auth, auth = pcall(require, "codetyper.core.llm.providers.copilot.auth")
      if ok_auth then
        auth.ensure_initialized()
        auth.state.oauth_token = oauth_token
        auth.state.github_token = nil
        auth.invalidate_valid_cache()
      end

      callback(true, nil)
    end)
  end)
end

return M
