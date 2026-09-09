--- Execute agent file operations — create files, modify buffers, manage imports
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Create a new file with content
---@param path string Absolute file path
---@param content string File content
---@return boolean success
---@return string|nil error
function M.create_file(path, content)
  if not content or content == "" then
    flog.warn("agent.exec", "refusing to create file with empty content: " .. path) -- TODO: remove after debugging
    return false, "Cannot create file: empty content"
  end

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  local f = io.open(path, "w")
  if not f then
    return false, "Cannot create file: " .. path
  end
  f:write(content)
  f:close()

  flog.info("agent.exec", "created: " .. path) -- TODO: remove after debugging

  -- Open the new file — but only if not already open in a buffer
  vim.schedule(function()
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      -- Already open — just reload its content
      local new_lines = vim.split(content, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    else
      -- First creation — open in a split
      vim.cmd("vsplit " .. vim.fn.fnameescape(path))
    end
    vim.notify("Created: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  end)

  return true
end

--- Modify a file using search/replace
---@param path string Absolute file path
---@param search string Exact code to find
---@param replace string Replacement code
---@param opts table|nil Options: { allow_empty = boolean (default false) }
---@return boolean success
---@return string|nil error
function M.modify_file(path, search, replace, opts)
  opts = opts or {}
  -- Read current content
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or not lines then
    return false, "Cannot read file: " .. path
  end

  local content = table.concat(lines, "\n")

  -- Find and replace (exact match)
  local escaped_search = search:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  local new_content, count = content:gsub(escaped_search, replace, 1)

  if count == 0 then
    -- Try with normalized whitespace (trim trailing spaces per line)
    local norm_content = content:gsub(" +\n", "\n")
    local norm_search = search:gsub(" +\n", "\n")
    local norm_escaped = norm_search:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    new_content, count = norm_content:gsub(norm_escaped, replace, 1)

    if count == 0 then
      flog.warn("agent.exec", "SEARCH text not found in " .. path) -- TODO: remove after debugging
      return false, "SEARCH text not found in file: " .. vim.fn.fnamemodify(path, ":t")
    end
  end

  -- Refuse to write back a collapsed/empty result unless explicitly allowed —
  -- this is the confirmed data-loss vector: a failed/degenerate replace must
  -- never silently empty a real file on disk.
  if (not new_content or new_content == "") and not opts.allow_empty then
    flog.warn("agent.exec", "refusing to write empty content: " .. path) -- TODO: remove after debugging
    return false, "Refusing to write empty content: " .. path
  end

  -- Write back
  local new_lines = vim.split(new_content, "\n", { plain = true })
  local f = io.open(path, "w")
  if not f then
    return false, "Cannot write file: " .. path
  end
  f:write(new_content)
  f:close()

  flog.info("agent.exec", "modified: " .. path) -- TODO: remove after debugging

  -- Reload buffer if open
  vim.schedule(function()
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    end
    vim.notify("Modified: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  end)

  return true
end

--- Delete a file
---@param path string Absolute file path
---@return boolean success
---@return string|nil error
function M.delete_file(path)
  local ok, err = os.remove(path)
  if not ok then
    return false, "Cannot delete: " .. (err or path)
  end

  flog.info("agent.exec", "deleted: " .. path) -- TODO: remove after debugging

  vim.schedule(function()
    -- Close buffer if open
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    vim.notify("Deleted: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  end)

  return true
end

--- Execute a list of file operations (deduplicated — same path+action runs once)
---@param operations table[] FileOperation list from parse_response
---@return number applied Count of successful operations
---@return number failed Count of failed operations
---@return string[] errors List of error messages
function M.execute(operations)
  local applied = 0
  local failed = 0
  local errors = {}

  -- Deduplicate: keep only the LAST operation per path+action
  -- (the model may repeat the same FILE: block multiple times)
  local seen = {}
  local deduped = {}
  for i = #operations, 1, -1 do
    local op = operations[i]
    local key = (op.action or "") .. ":" .. (op.path or "")
    if not seen[key] then
      seen[key] = true
      table.insert(deduped, 1, op)
    end
  end

  flog.info("agent.exec", string.format(
    "executing: %d ops (%d deduplicated from %d)",
    #deduped, #operations - #deduped, #operations
  ))

  for _, op in ipairs(deduped) do
    local ok, err

    if op.action == "create" then
      ok, err = M.create_file(op.path, op.content)
    elseif op.action == "modify" then
      ok, err = M.modify_file(op.path, op.search, op.replace)
    elseif op.action == "delete" then
      ok, err = M.delete_file(op.path)
    else
      ok = false
      err = "Unknown action: " .. tostring(op.action)
    end

    if ok then
      applied = applied + 1
    else
      failed = failed + 1
      table.insert(errors, err or "Unknown error")
      flog.error("agent.exec", err or "Unknown error")
    end
  end

  flog.info("agent.exec", string.format("done: %d applied, %d failed", applied, failed)) -- TODO: remove after debugging

  if applied > 0 then
    vim.schedule(function()
      vim.notify(
        string.format("Agent: %d operation%s applied", applied, applied > 1 and "s" or ""),
        vim.log.levels.INFO
      )
    end)
  end
  if failed > 0 then
    vim.schedule(function()
      vim.notify(
        string.format("Agent: %d operation%s failed:\n%s", failed, failed > 1 and "s" or "", table.concat(errors, "\n")),
        vim.log.levels.WARN
      )
    end)
  end

  return applied, failed, errors
end

local MAX_TOOL_RESULT_CHARS = 4000

local REGISTRY_TOOL_NAMES = {
  codegraph_context = true,
  tokensave_search = true,
  context7_resolve_library = true,
  context7_query_docs = true,
  ask_user = true,
  add_import = true,
}

local function bounded_message(value, fallback)
  local message = type(value) == "string" and value or fallback
  message = (message or "tool request failed"):gsub("[%z\1-\31\127]", " ")
  return message:sub(1, 512)
end

local function bounded_result(value)
  if type(value) ~= "table" then
    return {
      status = "error",
      data = nil,
      error = "tool returned an invalid result",
      stale = true,
    }
  end

  local result = {
    status = type(value.status) == "string" and value.status or "error",
    data = value.data,
    error = value.error and bounded_message(value.error) or nil,
    stale = value.stale == true,
  }
  for _, field in ipairs({ "metadata", "index", "option" }) do
    if value[field] ~= nil then
      result[field] = value[field]
    end
  end

  if result.data ~= nil then
    local ok, encoded = pcall(vim.json.encode, result.data)
    if not ok or #encoded > MAX_TOOL_RESULT_CHARS then
      return {
        status = "error",
        data = nil,
        error = "tool result exceeds the 4000 character bound",
        stale = true,
      }
    end
  end
  return result
end

local function encode_result(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok or #encoded > MAX_TOOL_RESULT_CHARS then
    return vim.json.encode({
      status = "error",
      data = nil,
      error = "tool result exceeds the 4000 character bound",
      stale = true,
    })
  end
  return encoded
end

local function result_is_success(value)
  return value.status ~= "error" and value.status ~= "cancelled" and value.status ~= "timeout"
end

local function normalize_arguments(value)
  if type(value) == "string" then
    local ok, decoded = pcall(vim.json.decode, value)
    if ok and type(decoded) == "table" then
      return decoded
    end
    return {}
  end
  return type(value) == "table" and value or {}
end

--- Normalize text-marker and native structured calls into one internal shape.
---@param call table
---@return table normalized
local function normalize_tool_call(call)
  if type(call) ~= "table" then
    return { kind = "unknown", id = "", name = "", args = {} }
  end

  if call.type == "registry" then
    return {
      kind = "registry",
      id = call.id or call.tool_call_id or "",
      name = call.name or "",
      args = normalize_arguments(call.args or call.arguments),
    }
  end
  if call.type == "terminal" then
    return { kind = "terminal", id = call.id or "", name = "terminal", command = call.command or "" }
  end
  if call.type == "mcp" then
    return {
      kind = "mcp",
      id = call.id or call.tool_call_id or "",
      name = (call.server or "") .. "__" .. (call.tool or ""),
      server = call.server or "",
      tool = call.tool or "",
      args = normalize_arguments(call.args or call.arguments),
    }
  end

  local id = call.id or call.tool_call_id or ""
  local name = call.name
  local arguments = call.arguments
  if type(call["function"]) == "table" then
    name = call["function"].name
    arguments = call["function"].arguments
  end
  name = type(name) == "string" and name or ""

  if name == "terminal" then
    local args = normalize_arguments(arguments)
    return { kind = "terminal", id = id, name = name, command = args.command or "" }
  end
  if REGISTRY_TOOL_NAMES[name] then
    return { kind = "registry", id = id, name = name, args = normalize_arguments(arguments) }
  end

  local server, tool = name:match("^(.-)__(.+)$")
  if server and tool then
    return { kind = "mcp", id = id, name = name, server = server, tool = tool, args = normalize_arguments(arguments) }
  end
  return { kind = "unknown", id = id, name = name, args = normalize_arguments(arguments) }
end

local function mcp_tool_allowed(mcp, server, tool)
  if type(mcp.is_tool_allowed) == "function" then
    local ok, allowed = pcall(mcp.is_tool_allowed, server, tool)
    return ok and allowed == true
  end

  if type(mcp.get_tools_for_api) == "function" then
    local ok, tools = pcall(mcp.get_tools_for_api)
    if not ok or type(tools) ~= "table" then
      return false
    end
    local encoded = server .. "__" .. tool
    for _, definition in ipairs(tools) do
      local function_def = definition["function"] or definition
      if function_def and (function_def.name == encoded or (definition.server_name == server and function_def.name == tool)) then
        return true
      end
    end
  end
  return false
end

local function display_result(title, content)
  vim.schedule(function()
    local ok, explain = pcall(require, "codetyper.window.explain")
    if not ok or not explain then
      return
    end
    local previous = explain._last_content
    local combined = previous and previous ~= "" and previous .. "\n\n" .. content or content
    if explain.is_open() then
      explain.update(combined)
    else
      explain.show("Tool Result", combined)
    end
    explain._last_content = combined
  end)
end

local function result_entry(call, value, kind)
  local bounded = bounded_result(value)
  local entry = {
    type = kind or "agent",
    id = call.id,
    tool_call_id = call.id,
    name = call.name,
    result = bounded,
    output = encode_result(bounded),
    success = result_is_success(bounded),
  }
  if call.kind == "terminal" then
    entry.command = call.command
  elseif call.kind == "mcp" then
    entry.server = call.server
    entry.tool = call.tool
  end
  return entry
end

--- Execute text-marker or native structured tool calls through one boundary.
--- Local registry calls are serialized and always run before remote MCP calls.
---@param tool_calls table[] From parse_response or a native provider
---@param callback fun(results: table[]) Called exactly once
---@param opts table|nil {registry,mcp,terminal,timeout_ms}
---@return table handle
function M.execute_tools(tool_calls, callback, opts)
  opts = opts or {}
  callback = callback or function() end
  local normalized = {}
  for index, raw_call in ipairs(tool_calls or {}) do
    local call = normalize_tool_call(raw_call)
    call.original_index = index
    normalized[#normalized + 1] = call
  end

  local tasks = {}
  for _, call in ipairs(normalized) do
    if call.kind ~= "mcp" then
      tasks[#tasks + 1] = call
    end
  end
  for _, call in ipairs(normalized) do
    if call.kind == "mcp" then
      tasks[#tasks + 1] = call
    end
  end

  local results = {}
  local finished = false
  local cancelled = false
  local task_position = 0
  local active_handle
  local active_call
  local timeout_timer
  local handle = {}

  local function stop_timeout()
    if timeout_timer then
      pcall(function() timeout_timer:stop() end)
      timeout_timer = nil
    end
  end

  local function complete_all()
    if finished then
      return
    end
    finished = true
    stop_timeout()
    pcall(callback, results)
  end

  local function fill_cancelled_results()
    for _, call in ipairs(normalized) do
      if not results[call.original_index] then
        results[call.original_index] = result_entry(call, {
          status = "cancelled",
          data = nil,
          error = "tool request cancelled",
          stale = false,
        }, call.kind == "mcp" and "mcp" or "agent")
      end
    end
  end

  local run_next
  local function finish_task(call, value, kind, continue)
    if call.completed then
      return
    end
    call.completed = true
    stop_timeout()
    active_handle = nil
    active_call = nil
    results[call.original_index] = result_entry(call, value, kind)
    if continue and not cancelled then
      run_next()
    else
      if cancelled then
        fill_cancelled_results()
      end
      complete_all()
    end
  end

  local function schedule_timeout(call)
    local timeout_ms = tonumber(opts.timeout_ms)
    if timeout_ms and timeout_ms > 0 then
      timeout_timer = vim.defer_fn(function()
        if not call.completed then
          if active_handle and type(active_handle.cancel) == "function" then
            pcall(active_handle.cancel, active_handle)
          end
          finish_task(call, {
            status = "timeout",
            data = nil,
            error = "tool request timed out",
            stale = true,
          }, call.kind == "mcp" and "mcp" or "agent", true)
        end
      end, timeout_ms)
    end
  end

  local function invoke_registry(call, registry)
    if not registry or type(registry.dispatch) ~= "function" then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "agent tool registry is unavailable",
        stale = true,
      }, "agent", true)
      return
    end
    local ok, returned = pcall(registry.dispatch, call.name, call.args, function(value)
      finish_task(call, value, "agent", true)
    end, opts)
    if not ok then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "agent tool dispatch failed",
        stale = true,
      }, "agent", true)
      return
    end
    if type(returned) == "table" and not call.completed and active_call == call then
      active_handle = returned
    end
  end

  local function invoke_terminal(call, terminal)
    if type(call.command) ~= "string" or call.command:gsub("%s", "") == "" then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "terminal command is required",
        stale = false,
      }, "terminal", true)
      return
    end
    if not terminal or type(terminal.run_visible or terminal.run) ~= "function" then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "terminal tool is unavailable",
        stale = true,
      }, "terminal", true)
      return
    end
    if type(terminal.is_safe) == "function" then
      local safe, reason = terminal.is_safe(call.command)
      if not safe then
        finish_task(call, {
          status = "error",
          data = nil,
          error = reason or "terminal command blocked",
          stale = false,
        }, "terminal", true)
        return
      end
    end
    local run = terminal.run_visible or terminal.run
    local ok, returned = pcall(run, call.command, function(output, err)
      local content = output or err or "No output"
      display_result("Terminal", string.format("## Terminal: `%s`\n\n```\n%s\n```", call.command, content))
      finish_task(call, {
        status = err and "error" or "available",
        data = content:sub(1, MAX_TOOL_RESULT_CHARS),
        error = err,
        stale = false,
      }, "terminal", true)
    end)
    if not ok then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "terminal tool failed",
        stale = true,
      }, "terminal", true)
    elseif type(returned) == "table" and not call.completed and active_call == call then
      active_handle = returned
    end
  end

  local function invoke_mcp(call, mcp)
    if not mcp or type(mcp.call_tool) ~= "function" then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "MCP tool is unavailable",
        stale = true,
      }, "mcp", true)
      return
    end
    if not mcp_tool_allowed(mcp, call.server, call.tool) then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "MCP tool is not allowed",
        stale = false,
      }, "mcp", true)
      return
    end
    local ok, returned = pcall(mcp.call_tool, call.server, call.tool, call.args, function(output, err)
      local content = output or err or "No output"
      display_result("MCP", string.format("## MCP: %s/%s\n\n```\n%s\n```", call.server, call.tool, content))
      finish_task(call, {
        status = err and "error" or "available",
        data = content:sub(1, MAX_TOOL_RESULT_CHARS),
        error = err,
        stale = false,
      }, "mcp", true)
    end)
    if not ok then
      finish_task(call, {
        status = "error",
        data = nil,
        error = "MCP tool call failed",
        stale = true,
      }, "mcp", true)
    elseif type(returned) == "table" and not call.completed and active_call == call then
      active_handle = returned
    end
  end

  run_next = function()
    if finished then
      return
    end
    task_position = task_position + 1
    local call = tasks[task_position]
    if not call then
      complete_all()
      return
    end
    if cancelled then
      fill_cancelled_results()
      complete_all()
      return
    end

    active_call = call
    schedule_timeout(call)
    if call.kind == "registry" then
      invoke_registry(call, opts.registry or require("codetyper.core.agent.tools"))
    elseif call.kind == "terminal" then
      invoke_terminal(call, opts.terminal or require("codetyper.core.agent.terminal"))
    elseif call.kind == "mcp" then
      invoke_mcp(call, opts.mcp or require("codetyper.core.agent.mcp"))
    else
      finish_task(call, {
        status = "error",
        data = nil,
        error = "unknown or unsupported tool",
        stale = false,
      }, "agent", true)
    end
  end

  function handle.cancel()
    if finished or cancelled then
      return
    end
    cancelled = true
    if active_handle and type(active_handle.cancel) == "function" then
      pcall(active_handle.cancel, active_handle)
    end
    if active_call then
      finish_task(active_call, {
        status = "cancelled",
        data = nil,
        error = "tool request cancelled",
        stale = false,
      }, active_call.kind == "mcp" and "mcp" or "agent", false)
    else
      fill_cancelled_results()
      complete_all()
    end
  end

  if #tasks == 0 then
    complete_all()
    return handle
  end

  run_next()
  return handle
end

M.normalize_tool_call = normalize_tool_call

return M
