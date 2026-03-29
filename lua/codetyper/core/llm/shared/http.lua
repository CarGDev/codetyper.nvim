--- Shared HTTP client — curl via vim.fn.jobstart
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- POST request via curl
---@param url string
---@param headers string[] List of "Header: Value" strings
---@param body string JSON-encoded body
---@param callback fun(parsed: table|nil, error: string|nil)
function M.post(url, headers, body, callback)
  local cmd = { "curl", "-s", "-X", "POST", url }

  for _, header in ipairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  table.insert(cmd, "-d")
  table.insert(cmd, body)

  flog.debug("http", "POST " .. url .. " body_len=" .. #body) -- TODO: remove after debugging

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 or (data[1] == "" and #data == 1) then
        return
      end

      local response_text = table.concat(data, "\n")
      flog.debug("http", "response_len=" .. #response_text) -- TODO: remove after debugging

      local ok, parsed = pcall(vim.json.decode, response_text)
      if not ok then
        local error_msg = response_text
        if #error_msg > 200 then
          error_msg = error_msg:sub(1, 200) .. "..."
        end
        if response_text:match("<!DOCTYPE") or response_text:match("<html") then
          error_msg = "API returned HTML error page. Service may be unavailable."
        end
        vim.schedule(function()
          callback(nil, error_msg)
        end)
        return
      end

      vim.schedule(function()
        callback(parsed, nil)
      end)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        vim.schedule(function()
          callback(nil, "HTTP request failed: " .. table.concat(data, "\n"))
        end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          callback(nil, "curl exited with code: " .. code)
        end)
      end
    end,
  })
end

--- GET request via curl
---@param url string
---@param headers string[] List of "Header: Value" strings
---@param callback fun(parsed: table|nil, error: string|nil)
function M.get(url, headers, callback)
  local cmd = { "curl", "-s", "-X", "GET", url }

  for _, header in ipairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  flog.debug("http", "GET " .. url) -- TODO: remove after debugging

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 or (data[1] == "" and #data == 1) then
        return
      end

      local response_text = table.concat(data, "\n")
      local ok, parsed = pcall(vim.json.decode, response_text)
      if not ok then
        vim.schedule(function()
          callback(nil, "Failed to parse response")
        end)
        return
      end

      vim.schedule(function()
        callback(parsed, nil)
      end)
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        vim.schedule(function()
          callback(nil, "HTTP request failed: " .. table.concat(data, "\n"))
        end)
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.schedule(function()
          callback(nil, "curl exited with code: " .. code)
        end)
      end
    end,
  })
end

return M
