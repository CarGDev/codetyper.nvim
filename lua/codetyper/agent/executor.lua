---@mod codetyper.agent.executor Tool executor for agent system
---
--- Executes tools requested by the LLM and returns results.

local M = {}
local utils = require("codetyper.utils")

---@class ExecutionResult
---@field success boolean Whether the execution succeeded
---@field result string Result message or content
---@field requires_approval boolean Whether user approval is needed
---@field diff_data? DiffData Data for diff preview (if requires_approval)

---@class DiffData
---@field path string File path
---@field original string Original content
---@field modified string Modified content
---@field operation string Operation type: "edit", "create", "overwrite", "bash"

--- Execute a tool and return result via callback
---@param tool_name string Name of the tool to execute
---@param parameters table Tool parameters
---@param callback fun(result: ExecutionResult) Callback with result
function M.execute(tool_name, parameters, callback)
  local handlers = {
    read_file = M.handle_read_file,
    edit_file = M.handle_edit_file,
    write_file = M.handle_write_file,
    bash = M.handle_bash,
  }

  local handler = handlers[tool_name]
  if not handler then
    callback({
      success = false,
      result = "Unknown tool: " .. tool_name,
      requires_approval = false,
    })
    return
  end

  handler(parameters, callback)
end

--- Handle read_file tool
---@param params table { path: string }
---@param callback fun(result: ExecutionResult)
function M.handle_read_file(params, callback)
  local path = M.resolve_path(params.path)
  local content = utils.read_file(path)

  if content then
    callback({
      success = true,
      result = content,
      requires_approval = false,
    })
  else
    callback({
      success = false,
      result = "Could not read file: " .. path,
      requires_approval = false,
    })
  end
end

--- Handle edit_file tool
---@param params table { path: string, find: string, replace: string }
---@param callback fun(result: ExecutionResult)
function M.handle_edit_file(params, callback)
  local path = M.resolve_path(params.path)
  local original = utils.read_file(path)

  if not original then
    callback({
      success = false,
      result = "File not found: " .. path,
      requires_approval = false,
    })
    return
  end

  -- Try to find and replace the content
  local escaped_find = utils.escape_pattern(params.find)
  local new_content, count = original:gsub(escaped_find, params.replace, 1)

  if count == 0 then
    callback({
      success = false,
      result = "Could not find content to replace in: " .. path,
      requires_approval = false,
    })
    return
  end

  -- Requires user approval - show diff
  callback({
    success = true,
    result = "Edit prepared for: " .. path,
    requires_approval = true,
    diff_data = {
      path = path,
      original = original,
      modified = new_content,
      operation = "edit",
    },
  })
end

--- Handle write_file tool
---@param params table { path: string, content: string }
---@param callback fun(result: ExecutionResult)
function M.handle_write_file(params, callback)
  local path = M.resolve_path(params.path)
  local original = utils.read_file(path) or ""
  local operation = original == "" and "create" or "overwrite"

  -- Ensure parent directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" and dir ~= "." then
    utils.ensure_dir(dir)
  end

  callback({
    success = true,
    result = (operation == "create" and "Create" or "Overwrite") .. " prepared for: " .. path,
    requires_approval = true,
    diff_data = {
      path = path,
      original = original,
      modified = params.content,
      operation = operation,
    },
  })
end

--- Handle bash tool
---@param params table { command: string, timeout?: number }
---@param callback fun(result: ExecutionResult)
function M.handle_bash(params, callback)
  local command = params.command

  -- Requires user approval first
  callback({
    success = true,
    result = "Command: " .. command,
    requires_approval = true,
    diff_data = {
      path = "[bash]",
      original = "",
      modified = "$ " .. command,
      operation = "bash",
    },
    bash_command = command,
    bash_timeout = params.timeout or 30000,
  })
end

--- Actually apply an approved change
---@param diff_data DiffData The diff data to apply
---@param callback fun(result: ExecutionResult)
function M.apply_change(diff_data, callback)
  if diff_data.operation == "bash" then
    -- Extract command from modified (remove "$ " prefix)
    local command = diff_data.modified:gsub("^%$ ", "")
    M.execute_bash_command(command, 30000, callback)
  else
    -- Write file
    local success = utils.write_file(diff_data.path, diff_data.modified)
    if success then
      -- Reload buffer if it's open
      M.reload_buffer_if_open(diff_data.path)
      callback({
        success = true,
        result = "Changes applied to: " .. diff_data.path,
        requires_approval = false,
      })
    else
      callback({
        success = false,
        result = "Failed to write: " .. diff_data.path,
        requires_approval = false,
      })
    end
  end
end

--- Execute a bash command
---@param command string Command to execute
---@param timeout number Timeout in milliseconds
---@param callback fun(result: ExecutionResult)
function M.execute_bash_command(command, timeout, callback)
  local stdout_data = {}
  local stderr_data = {}
  local job_id

  job_id = vim.fn.jobstart(command, {
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
      vim.schedule(function()
        local result = table.concat(stdout_data, "\n")
        if #stderr_data > 0 then
          if result ~= "" then
            result = result .. "\n"
          end
          result = result .. "STDERR:\n" .. table.concat(stderr_data, "\n")
        end
        result = result .. "\n[Exit code: " .. exit_code .. "]"

        callback({
          success = exit_code == 0,
          result = result,
          requires_approval = false,
        })
      end)
    end,
  })

  -- Set up timeout
  if job_id > 0 then
    vim.defer_fn(function()
      if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
        vim.fn.jobstop(job_id)
        vim.schedule(function()
          callback({
            success = false,
            result = "Command timed out after " .. timeout .. "ms",
            requires_approval = false,
          })
        end)
      end
    end, timeout)
  else
    callback({
      success = false,
      result = "Failed to start command",
      requires_approval = false,
    })
  end
end

--- Reload a buffer if it's currently open
---@param filepath string Path to the file
function M.reload_buffer_if_open(filepath)
  local full_path = vim.fn.fnamemodify(filepath, ":p")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name == full_path then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit!")
        end)
        break
      end
    end
  end
end

--- Resolve a path (expand ~ and make absolute if needed)
---@param path string Path to resolve
---@return string Resolved path
function M.resolve_path(path)
  -- Expand ~ to home directory
  local expanded = vim.fn.expand(path)

  -- If relative, make it relative to project root or cwd
  if not vim.startswith(expanded, "/") then
    local root = utils.get_project_root() or vim.fn.getcwd()
    expanded = root .. "/" .. expanded
  end

  return vim.fn.fnamemodify(expanded, ":p")
end

return M
