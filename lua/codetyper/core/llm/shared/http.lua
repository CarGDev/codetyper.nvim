--- Shared HTTP client — curl via vim.fn.jobstart
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- POST request via curl
---@param url string
---@param headers string[] List of "Header: Value" strings
---@param body string JSON-encoded body
---@param callback fun(parsed: table|nil, error: string|nil)
function M.post(url, headers, body, callback)
  -- Write body to temp file to avoid shell argument limits with large prompts
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  if not f then
    callback(nil, "Failed to create temp file for request body")
    return
  end
  f:write(body)
  f:close()

  local cmd = { "curl", "-s", "-X", "POST", url }

  for _, header in ipairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  table.insert(cmd, "-d")
  table.insert(cmd, "@" .. tmp)

  flog.debug("http", "POST " .. url .. " body_len=" .. #body) -- TODO: remove after debugging

  local done = false
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if done then return end
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
        done = true
        vim.schedule(function()
          callback(nil, error_msg)
        end)
        return
      end

      done = true
      vim.schedule(function()
        callback(parsed, nil)
      end)
    end,
    on_stderr = function(_, data)
      if done then return end
      if data and #data > 0 and data[1] ~= "" then
        done = true
        vim.schedule(function()
          callback(nil, "HTTP request failed: " .. table.concat(data, "\n"))
        end)
      end
    end,
    on_exit = function(_, code)
      -- Clean up temp file
      os.remove(tmp)
      if done then return end
      if code ~= 0 then
        done = true
        vim.schedule(function()
          callback(nil, "curl exited with code: " .. code .. ", check the /tmp/codetyper.tmp.log")
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

  local done = false
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if done then return end
      if not data or #data == 0 or (data[1] == "" and #data == 1) then
        return
      end

      local response_text = table.concat(data, "\n")
      local ok, parsed = pcall(vim.json.decode, response_text)
      if not ok then
        done = true
        vim.schedule(function()
          callback(nil, "Failed to parse response")
        end)
        return
      end

      done = true
      vim.schedule(function()
        callback(parsed, nil)
      end)
    end,
    on_stderr = function(_, data)
      if done then return end
      if data and #data > 0 and data[1] ~= "" then
        done = true
        vim.schedule(function()
          callback(nil, "HTTP request failed: " .. table.concat(data, "\n"))
        end)
      end
    end,
    on_exit = function(_, code)
      if done then return end
      if code ~= 0 then
        done = true
        vim.schedule(function()
          callback(nil, "curl exited with code: " .. code)
        end)
      end
    end,
  })
end

--- Streaming POST request via curl (SSE format)
--- Sends chunks as they arrive instead of buffering the full response.
---@param url string
---@param headers string[] List of "Header: Value" strings
---@param body string JSON-encoded body
---@param opts table { on_chunk: fun(json_str), on_done: fun(), on_error: fun(err) }
---@return number job_id (for cancellation via vim.fn.jobstop)
function M.post_stream(url, headers, body, opts)
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  if not f then
    vim.schedule(function()
      opts.on_error("Failed to create temp file for request body")
    end)
    return -1
  end
  f:write(body)
  f:close()

  local cmd = { "curl", "-s", "-N", "-X", "POST", url }

  for _, header in ipairs(headers) do
    table.insert(cmd, "-H")
    table.insert(cmd, header)
  end

  table.insert(cmd, "-d")
  table.insert(cmd, "@" .. tmp)

  flog.debug("http", "POST_STREAM " .. url .. " body_len=" .. #body)

  local done = false
  local line_buffer = ""

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if done then return end
      if not data then return end

      -- Append incoming data to line buffer and process complete lines
      for _, chunk in ipairs(data) do
        line_buffer = line_buffer .. chunk .. "\n"
      end
      -- vim.fn.jobstart splits on \n, each element in data is a line fragment.
      -- The last element is either "" (line complete) or a partial (more coming).
      -- Remove the trailing \n we added for the last element if it was partial.
      if data[#data] ~= "" then
        line_buffer = line_buffer:sub(1, -2)
      end

      -- Process all complete lines
      local remaining = ""
      for line in line_buffer:gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.-)%s*$") or ""

        -- Skip empty lines (SSE separators) and event type lines
        if trimmed == "" or trimmed:match("^event:") or trimmed:match("^:") then
          -- skip
        elseif trimmed:match("^data:%s*") then
          local payload = trimmed:gsub("^data:%s*", "")
          if payload == "[DONE]" then
            done = true
            vim.schedule(function()
              opts.on_done()
            end)
            return
          else
            vim.schedule(function()
              opts.on_chunk(payload)
            end)
          end
        end
      end

      -- Keep the last incomplete line (no trailing \n)
      local last_newline = line_buffer:match(".*\n()")
      if last_newline then
        remaining = line_buffer:sub(last_newline)
      else
        remaining = line_buffer
      end
      line_buffer = remaining
    end,
    on_stderr = function(_, data)
      if done then return end
      if data and #data > 0 and data[1] ~= "" then
        local err_text = table.concat(data, "\n")
        -- Ignore curl progress output
        if not err_text:match("^%s*$") then
          flog.debug("http", "stream stderr: " .. err_text:sub(1, 200))
        end
      end
    end,
    on_exit = function(_, code)
      os.remove(tmp)
      if done then return end
      done = true
      if code ~= 0 then
        vim.schedule(function()
          opts.on_error("curl stream exited with code: " .. code)
        end)
      else
        -- Stream ended without [DONE] — still call on_done
        vim.schedule(function()
          opts.on_done()
        end)
      end
    end,
  })

  return job_id
end

return M
