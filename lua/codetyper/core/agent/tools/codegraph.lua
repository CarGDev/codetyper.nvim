--- Read-only CodeGraph JSON adapter.

local local_cli = require("codetyper.core.agent.tools.local_cli")

local M = {}

M.DEFAULT_MAX_NODES = 20
M.MAX_MAX_NODES = 100

local function result(status, data, error, stale, metadata)
  return {
    status = status,
    data = data,
    error = error and local_cli.safe_error(error, "CodeGraph request failed") or nil,
    stale = stale == true,
    metadata = metadata,
  }
end

local function is_executable(opts)
  if type(opts.executable) == "function" then
    local ok, value = pcall(opts.executable, "codegraph")
    return ok and (value == true or value == 1)
  end
  return vim.fn.executable("codegraph") == 1
end

local function root_for(opts)
  local root = opts.root or opts.project_root
  if not root then
    local ok, utils = pcall(require, "codetyper.support.utils")
    if ok and utils.get_project_root then
      root = utils.get_project_root()
    else
      root = vim.fn.getcwd()
    end
  end
  return local_cli.validate_root(root)
end

local function validate_args(args)
  if type(args) ~= "table" then
    return nil, "tool arguments must be an object"
  end
  for key in pairs(args) do
    if key ~= "query" and key ~= "max_nodes" and key ~= "no_code" then
      return nil, "unexpected tool argument: " .. tostring(key)
    end
  end

  local query = args.query
  if type(query) ~= "string" then
    return nil, "query must be a string"
  end
  query = query:gsub("^%s+", ""):gsub("%s+$", "")
  if query == "" or query:find("[%z\1-\31\127]") then
    return nil, "query must be non-empty text"
  end
  if #query > 2000 then
    return nil, "query is too long"
  end

  local max_nodes = args.max_nodes
  if max_nodes == nil then
    max_nodes = M.DEFAULT_MAX_NODES
  end
  if
    type(max_nodes) ~= "number"
    or max_nodes ~= math.floor(max_nodes)
    or max_nodes < 1
    or max_nodes > M.MAX_MAX_NODES
  then
    return nil, "max_nodes must be an integer from 1 to 100"
  end

  local no_code = args.no_code
  if no_code == nil then
    no_code = false
  end
  if type(no_code) ~= "boolean" then
    return nil, "no_code must be boolean"
  end

  return { query = query, max_nodes = max_nodes, no_code = no_code }, nil
end

local function cli_for(opts)
  return opts.cli or local_cli
end

local function cli_options(opts, root)
  return {
    cwd = root,
    timeout_ms = opts.timeout_ms,
    max_stdout = opts.max_stdout or local_cli.DEFAULT_MAX_STDOUT,
    max_stderr = opts.max_stderr or local_cli.DEFAULT_MAX_STDERR,
    runner = opts.runner,
  }
end

local function response_error(response, label)
  response = type(response) == "table" and response or {}
  if response.cancelled then
    return result("cancelled", nil, label .. " operation cancelled", true)
  end
  if response.timed_out then
    return result("error", nil, label .. " operation timed out", true)
  end
  if response.exit_code ~= 0 then
    return result("error", nil, label .. " command failed", true)
  end
  return nil
end

local function decode_response(response, label)
  local failed = response_error(response, label)
  if failed then
    return nil, failed
  end
  local value, decode_error = local_cli.decode_json(local_cli.bound_text(response.stdout, local_cli.DEFAULT_MAX_STDOUT))
  if value == nil then
    return nil, result("error", nil, label .. " returned malformed JSON: " .. tostring(decode_error), true)
  end
  return value, nil
end

local function pending_status(status)
  return status.pending == true
    or status.indexing == true
    or status.state == "pending"
    or status.state == "indexing"
    or status.status == "pending"
    or status.status == "indexing"
end

local function status_metadata(status)
  return {
    initialized = status.initialized == true,
    pending = pending_status(status),
    last_indexed = status.lastIndexed or status.last_indexed,
    project_path = status.projectPath or status.project_path,
  }
end

local function run_query(operation, args, callback, opts)
  opts = opts or {}
  local normalized, args_error = validate_args(args)
  if not normalized then
    callback(result("error", nil, args_error, false))
    return { cancel = function() end }
  end

  local root, root_error = root_for(opts)
  if not root then
    callback(result("error", nil, root_error, false))
    return { cancel = function() end }
  end
  if not is_executable(opts) then
    callback(result("unavailable", nil, "CodeGraph executable is unavailable", true))
    return { cancel = function() end }
  end

  local cli = cli_for(opts)
  local options = cli_options(opts, root)
  local complete = false
  local active_handle
  local function emit(value)
    if complete then
      return
    end
    complete = true
    callback(value)
  end
  local outer_handle = {
    cancel = function()
      if complete then
        return
      end
      if active_handle and type(active_handle.cancel) == "function" then
        pcall(active_handle.cancel, active_handle)
      end
      emit(result("cancelled", nil, "CodeGraph operation cancelled", true))
    end,
  }

  local status_handle = cli.run({ "codegraph", "status", "--json", root }, options, function(status_response)
    active_handle = nil
    local status, status_error = decode_response(status_response, "CodeGraph status")
    if status_error then
      emit(status_error)
      return
    end
    if type(status) ~= "table" then
      emit(result("error", nil, "CodeGraph status must be a JSON object", true))
      return
    end

    local metadata = status_metadata(status)
    if pending_status(status) or status.stale == true then
      emit(result("stale", nil, "CodeGraph index is stale or still indexing", true, metadata))
      return
    end
    if status.initialized ~= true then
      emit(result("unavailable", nil, "CodeGraph project is not initialized", true, metadata))
      return
    end

    local argv = {
      "codegraph",
      operation,
      normalized.query,
      "--path",
      root,
      "--format",
      "json",
      "--max-nodes",
      tostring(normalized.max_nodes),
    }
    if normalized.no_code then
      table.insert(argv, "--no-code")
    end

    active_handle = cli.run(argv, options, function(query_response)
      local data, query_error = decode_response(query_response, "CodeGraph " .. operation)
      if query_error then
        emit(query_error)
        return
      end
      if type(data) ~= "table" then
        emit(result("error", nil, "CodeGraph " .. operation .. " returned invalid JSON", true, metadata))
        return
      end
      emit(result("available", data, nil, false, metadata))
    end)
  end)
  if not active_handle then
    active_handle = status_handle
  end

  return outer_handle
end

--- Run CodeGraph's read-only context operation.
function M.context(args, callback, opts)
  return run_query("context", args, callback, opts)
end

--- Run CodeGraph's read-only explore operation.
function M.explore(args, callback, opts)
  return run_query("explore", args, callback, opts)
end

--- Report cheap availability metadata without running a command.
function M.availability(opts)
  opts = opts or {}
  local root, root_error = root_for(opts)
  if not root then
    return { available = false, stale = true, error = root_error }
  end
  if not is_executable(opts) then
    return { available = false, stale = true, error = "CodeGraph executable is unavailable" }
  end
  return { available = true, stale = false, root = root }
end

M.validate = validate_args

return M
