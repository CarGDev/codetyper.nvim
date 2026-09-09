--- Read-only TokenSave search adapter.

local local_cli = require("codetyper.core.agent.tools.local_cli")

local M = {}

M.DEFAULT_LIMIT = 10
M.MAX_LIMIT = 100

local function result(status, data, error, stale, metadata)
  return {
    status = status,
    data = data,
    error = error and local_cli.safe_error(error, "TokenSave request failed") or nil,
    stale = stale == true,
    metadata = metadata,
  }
end

local function is_executable(opts)
  if type(opts.executable) == "function" then
    local ok, value = pcall(opts.executable, "tokensave")
    return ok and (value == true or value == 1)
  end
  return vim.fn.executable("tokensave") == 1
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
    if key ~= "query" and key ~= "limit" then
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

  local limit = args.limit
  if limit == nil then
    limit = M.DEFAULT_LIMIT
  end
  if type(limit) ~= "number" or limit ~= math.floor(limit) or limit < 1 or limit > M.MAX_LIMIT then
    return nil, "limit must be an integer from 1 to 100"
  end

  return { query = query, limit = limit }, nil
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
    or status.state == "stale"
    or status.status == "stale"
end

local function find_branch_entry(metadata, branch)
  local entry = metadata[branch]
  if not entry and type(metadata.branches) == "table" then
    entry = metadata.branches[branch]
  end
  if type(entry) ~= "table" then
    return nil
  end
  if type(entry.db_file) ~= "string" or entry.db_file == "" then
    return nil
  end
  if entry.db_file:match("^/") or entry.db_file:find("%.%.[/\\]") or entry.db_file:find("[%z\1-\31\127]") then
    return nil
  end
  return entry
end

local function read_markers(root)
  local config_path = root .. "/.tokensave/config.json"
  local branch_path = root .. "/.tokensave/branch-meta.json"
  if vim.fn.filereadable(config_path) ~= 1 or vim.fn.filereadable(branch_path) ~= 1 then
    return nil, result("unavailable", nil, "TokenSave project markers are unavailable", true)
  end

  local config, config_error = local_cli.read_json_file(config_path)
  if not config then
    return nil, result("error", nil, "TokenSave config is invalid: " .. tostring(config_error), true)
  end
  if config.root_dir and type(config.root_dir) ~= "string" then
    return nil, result("error", nil, "TokenSave config has an invalid project root", true)
  end
  if config.root_dir then
    local configured_root = local_cli.validate_root(config.root_dir)
    if not configured_root or configured_root ~= root then
      return nil, result("unavailable", nil, "TokenSave config belongs to another project root", true)
    end
  end

  local metadata, metadata_error = local_cli.read_json_file(branch_path)
  if not metadata then
    return nil, result("error", nil, "TokenSave branch metadata is invalid: " .. tostring(metadata_error), true)
  end
  return { config = config, branches = metadata }, nil
end

local function current_branch(root, opts, cli, options, callback)
  if type(opts.branch) == "string" and opts.branch ~= "" then
    local branch = opts.branch:gsub("^%s+", ""):gsub("%s+$", "")
    if branch == "" or branch:find("[%z\1-\31\127]") or #branch > 255 then
      callback(nil, result("error", nil, "branch metadata is invalid", true))
    else
      callback(branch)
    end
    return { cancel = function() end }
  end

  return cli.run({ "git", "-C", root, "branch", "--show-current" }, options, function(response)
    local failed = response_error(response, "Git branch")
    if failed then
      callback(nil, failed)
      return
    end
    local branch = local_cli.bound_text(response.stdout, 256):gsub("^%s+", ""):gsub("%s+$", "")
    if branch == "" or branch:find("[%z\1-\31\127]") then
      callback(nil, result("stale", nil, "current Git branch is unavailable", true))
      return
    end
    callback(branch)
  end)
end

local function parse_search_payload(value)
  if type(value) == "string" then
    local inner, err = local_cli.decode_json(value)
    if not inner then
      return nil, err
    end
    return parse_search_payload(inner)
  end

  if type(value) ~= "table" then
    return nil, "search JSON must be an object or array"
  end

  if type(value.content) == "table" then
    local candidates = {}
    if value.content[2] and value.content[2].text then
      table.insert(candidates, value.content[2].text)
    end
    if value.content[1] and value.content[1].text then
      table.insert(candidates, value.content[1].text)
    end
    for index, item in ipairs(value.content) do
      if index ~= 1 and index ~= 2 and type(item) == "table" and item.text then
        table.insert(candidates, item.text)
      end
    end
    for _, text in ipairs(candidates) do
      local parsed = parse_search_payload(text)
      if parsed then
        return parsed, nil
      end
    end
    return nil, "TokenSave content did not contain JSON text"
  end

  return value, nil
end

local function run_search(args, callback, opts)
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
    callback(result("unavailable", nil, "TokenSave executable is unavailable", true))
    return { cancel = function() end }
  end

  local markers, marker_error = read_markers(root)
  if not markers then
    callback(marker_error)
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
      emit(result("cancelled", nil, "TokenSave operation cancelled", true))
    end,
  }

  local branch_handle = current_branch(root, opts, cli, options, function(branch, branch_error)
    active_handle = nil
    if branch_error then
      emit(branch_error)
      return
    end

    local branch_entry = find_branch_entry(markers.branches, branch)
    if not branch_entry then
      emit(result("stale", nil, "TokenSave has no index mapping for the current branch", true, { branch = branch }))
      return
    end

    local status_handle = cli.run({ "tokensave", "status", "--json" }, options, function(status_response)
      active_handle = nil
      local status, status_error = decode_response(status_response, "TokenSave status")
      if status_error then
        emit(status_error)
        return
      end
      if type(status) ~= "table" then
        emit(result("error", nil, "TokenSave status must be a JSON object", true, { branch = branch }))
        return
      end
      local has_status_fields = status.initialized ~= nil
        or status.ready ~= nil
        or status.status ~= nil
        or status.state ~= nil
      if not has_status_fields then
        emit(result("error", nil, "TokenSave status is missing readiness metadata", true, { branch = branch }))
        return
      end
      if pending_status(status) or status.stale == true then
        emit(result("stale", nil, "TokenSave index is stale or still indexing", true, { branch = branch }))
        return
      end
      if status.initialized == false or status.ready == false or status.status == "uninitialized" then
        emit(result("unavailable", nil, "TokenSave project is not initialized", true, { branch = branch }))
        return
      end

      active_handle = cli.run(
        {
          "tokensave",
          "tool",
          "search",
          "--query",
          normalized.query,
          "--limit",
          tostring(normalized.limit),
          "--json",
        },
        options,
        function(search_response)
          local value, search_error = decode_response(search_response, "TokenSave search")
          if search_error then
            emit(search_error)
            return
          end
          local data, payload_error = parse_search_payload(value)
          if not data then
            emit(
              result(
                "error",
                nil,
                "TokenSave search returned malformed JSON: " .. tostring(payload_error),
                true,
                { branch = branch }
              )
            )
            return
          end
          emit(result("available", data, nil, false, { branch = branch, db_file = branch_entry.db_file }))
        end
      )
    end)
    if not active_handle then
      active_handle = status_handle
    end
  end)
  if not active_handle then
    active_handle = branch_handle
  end

  return outer_handle
end

--- Run the read-only TokenSave search tool.
function M.search(args, callback, opts)
  return run_search(args, callback, opts)
end

--- Report marker and executable availability without reading the index.
function M.availability(opts)
  opts = opts or {}
  local root, root_error = root_for(opts)
  if not root then
    return { available = false, stale = true, error = root_error }
  end
  if not is_executable(opts) then
    return { available = false, stale = true, error = "TokenSave executable is unavailable" }
  end
  if
    vim.fn.filereadable(root .. "/.tokensave/config.json") ~= 1
    or vim.fn.filereadable(root .. "/.tokensave/branch-meta.json") ~= 1
  then
    return { available = false, stale = true, error = "TokenSave project markers are unavailable" }
  end
  return { available = true, stale = false, root = root }
end

M.validate = validate_args
M.parse_search_payload = parse_search_payload

return M
