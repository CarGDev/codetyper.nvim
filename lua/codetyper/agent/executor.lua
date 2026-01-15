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
    delete_file = M.handle_delete_file,
    list_directory = M.handle_list_directory,
    search_files = M.handle_search_files,
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

--- Handle delete_file tool
---@param params table { path: string, reason: string }
---@param callback fun(result: ExecutionResult)
function M.handle_delete_file(params, callback)
  local path = M.resolve_path(params.path)
  local reason = params.reason or "No reason provided"

  -- Check if file exists
  if not utils.file_exists(path) then
    callback({
      success = false,
      result = "File not found: " .. path,
      requires_approval = false,
    })
    return
  end

  -- Read content for showing in diff (so user knows what they're deleting)
  local content = utils.read_file(path) or "[Could not read file]"

  callback({
    success = true,
    result = "Delete: " .. path .. " (" .. reason .. ")",
    requires_approval = true,
    diff_data = {
      path = path,
      original = content,
      modified = "", -- Empty = deletion
      operation = "delete",
      reason = reason,
    },
  })
end

--- Handle list_directory tool
---@param params table { path?: string, recursive?: boolean }
---@param callback fun(result: ExecutionResult)
function M.handle_list_directory(params, callback)
  local path = params.path and M.resolve_path(params.path) or (utils.get_project_root() or vim.fn.getcwd())
  local recursive = params.recursive or false

  -- Use vim.fn.readdir or glob for directory listing
  local entries = {}
  local function list_dir(dir, depth)
    if depth > 3 then
      return
    end

    local ok, files = pcall(vim.fn.readdir, dir)
    if not ok or not files then
      return
    end

    for _, name in ipairs(files) do
      if name ~= "." and name ~= ".." and not name:match("^%.git$") and not name:match("^node_modules$") then
        local full_path = dir .. "/" .. name
        local stat = vim.loop.fs_stat(full_path)
        if stat then
          local prefix = string.rep("  ", depth)
          local type_indicator = stat.type == "directory" and "/" or ""
          table.insert(entries, prefix .. name .. type_indicator)

          if recursive and stat.type == "directory" then
            list_dir(full_path, depth + 1)
          end
        end
      end
    end
  end

  list_dir(path, 0)

  local result = "Directory: " .. path .. "\n\n" .. table.concat(entries, "\n")

  callback({
    success = true,
    result = result,
    requires_approval = false,
  })
end

--- Handle search_files tool
---@param params table { pattern?: string, content?: string, path?: string }
---@param callback fun(result: ExecutionResult)
function M.handle_search_files(params, callback)
  local search_path = params.path and M.resolve_path(params.path) or (utils.get_project_root() or vim.fn.getcwd())
  local pattern = params.pattern
  local content_search = params.content

  local results = {}

  if pattern then
    -- Search by file name pattern using glob
    local glob_pattern = search_path .. "/**/" .. pattern
    local files = vim.fn.glob(glob_pattern, false, true)

    for _, file in ipairs(files) do
      -- Skip common ignore patterns
      if not file:match("node_modules") and not file:match("%.git/") then
        table.insert(results, file:gsub(search_path .. "/", ""))
      end
    end
  end

  if content_search then
    -- Search by content using grep
    local grep_results = {}
    local grep_cmd = string.format("grep -rl '%s' '%s' 2>/dev/null | head -20", content_search:gsub("'", "\\'"), search_path)

    local handle = io.popen(grep_cmd)
    if handle then
      for line in handle:lines() do
        if not line:match("node_modules") and not line:match("%.git/") then
          table.insert(grep_results, line:gsub(search_path .. "/", ""))
        end
      end
      handle:close()
    end

    -- Merge with pattern results or use as primary results
    if #results == 0 then
      results = grep_results
    else
      -- Intersection of pattern and content results
      local pattern_set = {}
      for _, f in ipairs(results) do
        pattern_set[f] = true
      end
      results = {}
      for _, f in ipairs(grep_results) do
        if pattern_set[f] then
          table.insert(results, f)
        end
      end
    end
  end

  local result_text = "Search results"
  if pattern then
    result_text = result_text .. " (pattern: " .. pattern .. ")"
  end
  if content_search then
    result_text = result_text .. " (content: " .. content_search .. ")"
  end
  result_text = result_text .. ":\n\n"

  if #results == 0 then
    result_text = result_text .. "No files found."
  else
    result_text = result_text .. table.concat(results, "\n")
  end

  callback({
    success = true,
    result = result_text,
    requires_approval = false,
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
  elseif diff_data.operation == "delete" then
    -- Delete file
    local ok, err = os.remove(diff_data.path)
    if ok then
      -- Close buffer if it's open
      M.close_buffer_if_open(diff_data.path)
      callback({
        success = true,
        result = "Deleted: " .. diff_data.path,
        requires_approval = false,
      })
    else
      callback({
        success = false,
        result = "Failed to delete: " .. diff_data.path .. " (" .. (err or "unknown error") .. ")",
        requires_approval = false,
      })
    end
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

--- Close a buffer if it's currently open (for deleted files)
---@param filepath string Path to the file
function M.close_buffer_if_open(filepath)
  local full_path = vim.fn.fnamemodify(filepath, ":p")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name == full_path then
        -- Force close the buffer
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
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
