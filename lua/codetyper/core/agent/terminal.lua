--- Terminal command execution for agent tool calls
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Dangerous command patterns that should never auto-execute
local BLOCKED_PATTERNS = {
  "^rm %-rf",
  "^rm %-r /",
  "^sudo ",
  "^chmod 777",
  "^dd if=",
  "^mkfs",
  "^:(){ :|:& };:",
  "^curl.-| sh",
  "^wget.-| sh",
}

--- Check if a command is safe to run
---@param cmd string
---@return boolean safe
---@return string|nil reason
function M.is_safe(cmd)
  for _, pattern in ipairs(BLOCKED_PATTERNS) do
    if cmd:match(pattern) then
      return false, "Blocked: matches dangerous pattern"
    end
  end
  return true
end

--- Run a shell command and return output
---@param cmd string Shell command
---@param callback fun(output: string|nil, error: string|nil, exit_code: number)
---@param opts table|nil { timeout_ms: number, cwd: string }
function M.run(cmd, callback, opts)
  opts = opts or {}
  local timeout = opts.timeout_ms or 30000
  local cwd = opts.cwd or vim.fn.getcwd()

  -- Safety check
  local safe, reason = M.is_safe(cmd)
  if not safe then
    flog.warn("terminal", "blocked command: " .. cmd .. " (" .. reason .. ")") -- TODO: remove after debugging
    callback(nil, reason, -1)
    return
  end

  flog.info("terminal", "running: " .. cmd:sub(1, 100)) -- TODO: remove after debugging

  local stdout_data = {}
  local stderr_data = {}

  local job_id = vim.fn.jobstart({ "sh", "-c", cmd }, {
    cwd = cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local output = table.concat(stdout_data, "\n")
      local err_output = table.concat(stderr_data, "\n")

      flog.info("terminal", string.format( -- TODO: remove after debugging
        "exit=%d stdout=%d stderr=%d", exit_code, #output, #err_output
      ))

      -- Combine stdout and stderr for the result
      local full_output = output
      if err_output ~= "" then
        full_output = full_output .. "\n[stderr]\n" .. err_output
      end

      -- Truncate long outputs
      if #full_output > 10000 then
        full_output = full_output:sub(1, 9900) .. "\n...[truncated]"
      end

      vim.schedule(function()
        if exit_code ~= 0 and output == "" then
          callback(nil, err_output ~= "" and err_output or ("Command failed with exit code " .. exit_code), exit_code)
        else
          callback(full_output, nil, exit_code)
        end
      end)
    end,
  })

  -- Timeout
  if job_id > 0 then
    vim.defer_fn(function()
      if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
        vim.fn.jobstop(job_id)
        vim.schedule(function()
          callback(nil, "Command timed out after " .. (timeout / 1000) .. "s", -1)
        end)
      end
    end, timeout)
  end
end

return M
