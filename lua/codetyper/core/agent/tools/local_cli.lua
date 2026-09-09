--- Safe asynchronous argv execution shared by local context adapters.

local M = {}

M.DEFAULT_TIMEOUT_MS = 10000
M.MAX_TIMEOUT_MS = 120000
M.DEFAULT_MAX_STDOUT = 4000
M.DEFAULT_MAX_STDERR = 4000
M.MAX_ERROR = 512

local function bounded_text(value, limit)
  if type(value) ~= "string" then
    return ""
  end

  value = value:gsub("%z", "")
  if #value <= limit then
    return value
  end
  if limit <= 16 then
    return value:sub(1, limit)
  end
  return value:sub(1, math.max(0, limit - 16)) .. "\n...(truncated)"
end

M.bound_text = bounded_text

--- Convert an external diagnostic into a short, non-secret message.
---@param value any
---@param fallback string
---@return string
function M.safe_error(value, fallback)
  local message = type(value) == "string" and value or ""
  message = message:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  local lower = message:lower()
  if
    lower:find("api[_%-]?key", 1, false)
    or lower:find("authorization", 1, true)
    or lower:find("bearer", 1, true)
    or lower:find("password", 1, true)
    or lower:find("secret", 1, true)
    or lower:find("credential", 1, true)
    or lower:find("access[_%-]?token", 1, false)
  then
    message = "external command reported a sensitive diagnostic"
  end

  if message == "" then
    message = fallback
  end
  return bounded_text(message, M.MAX_ERROR)
end

--- Decode JSON without exposing the input in an error.
---@param text string
---@return any value
---@return string|nil error
function M.decode_json(text)
  if type(text) ~= "string" or text == "" then
    return nil, "empty JSON output"
  end

  local ok, value = pcall(vim.json.decode, text)
  if not ok then
    return nil, "malformed JSON output"
  end
  return value, nil
end

--- Read and decode a JSON marker file. The file contents never enter an error.
---@param path string
---@return table|nil value
---@return string|nil error
function M.read_json_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "marker file is unavailable"
  end

  local content = file:read("*a")
  file:close()
  local value, err = M.decode_json(content)
  if type(value) ~= "table" then
    return nil, err or "marker JSON must be an object"
  end
  return value, nil
end

--- Normalize a project root and reject paths that cannot be used as a cwd.
---@param root any
---@return string|nil normalized
---@return string|nil error
function M.validate_root(root)
  if type(root) ~= "string" or root == "" or root:find("%z", 1, true) then
    return nil, "project root is required"
  end
  if not root:match("^/") then
    return nil, "project root must be absolute"
  end
  if vim.fn.isdirectory(root) ~= 1 then
    return nil, "project root is not a directory"
  end
  local normalized = vim.fn.fnamemodify(root, ":p")
  if normalized ~= "/" then
    normalized = normalized:gsub("/+$", "")
  end
  return normalized, nil
end

local function normalize_argv(argv)
  if type(argv) ~= "table" or #argv == 0 then
    return nil, "argv is required"
  end

  local normalized = {}
  for index, value in ipairs(argv) do
    if type(value) ~= "string" or value == "" or value:find("%z", 1, true) then
      return nil, "argv contains an invalid argument"
    end
    normalized[index] = value
  end
  return normalized, nil
end

local function append_chunk(chunks, current_size, data, limit)
  if type(data) == "table" then
    data = table.concat(data, "\n")
  elseif type(data) ~= "string" then
    data = ""
  end

  if data == "" or current_size >= limit then
    return current_size
  end

  local room = limit - current_size
  if #data > room then
    table.insert(chunks, data:sub(1, room))
    return limit
  end

  table.insert(chunks, data)
  return current_size + #data
end

local function normalize_response(raw, max_stdout, max_stderr)
  raw = type(raw) == "table" and raw or {}
  local raw_stdout = type(raw.stdout) == "string" and raw.stdout or raw.output
  local raw_stderr = type(raw.stderr) == "string" and raw.stderr or ""
  local stdout = bounded_text(raw_stdout, max_stdout)
  local stderr = bounded_text(raw_stderr, max_stderr)
  return {
    stdout = stdout,
    stderr = stderr,
    exit_code = tonumber(raw.exit_code) or 0,
    cancelled = raw.cancelled == true,
    timed_out = raw.timed_out == true,
    stdout_truncated = raw.stdout_truncated == true or (type(raw_stdout) == "string" and #raw_stdout > max_stdout),
    stderr_truncated = raw.stderr_truncated == true or #raw_stderr > max_stderr,
  }
end

--- Run a fixed argv vector asynchronously.
---
--- Tests and adapters can inject opts.runner(argv, opts, done). The default
--- path uses vim.fn.jobstart directly and never passes argv through a shell.
---@param argv string[]
---@param opts table|nil
---@param callback fun(result: table)
---@return table handle with cancel()
function M.run(argv, opts, callback)
  opts = opts or {}
  local normalized, argv_error = normalize_argv(argv)
  local max_stdout = tonumber(opts.max_stdout) or M.DEFAULT_MAX_STDOUT
  local max_stderr = tonumber(opts.max_stderr) or M.DEFAULT_MAX_STDERR
  max_stdout = math.max(1, math.min(max_stdout, 100000))
  max_stderr = math.max(1, math.min(max_stderr, 100000))

  local completed = false
  local runner_handle
  local job_id

  local function finish(raw)
    if completed then
      return
    end
    completed = true
    callback(normalize_response(raw, max_stdout, max_stderr))
  end

  local handle = {}
  function handle.cancel()
    if completed then
      return
    end

    if runner_handle then
      local cancel = runner_handle
      if type(runner_handle) == "table" then
        cancel = runner_handle.cancel
      end
      if type(cancel) == "function" then
        pcall(cancel, runner_handle)
      end
    elseif job_id and job_id > 0 then
      pcall(vim.fn.jobstop, job_id)
    end
    finish({ cancelled = true, exit_code = -1, stderr = "operation cancelled" })
  end

  if not normalized then
    finish({ exit_code = -1, stderr = argv_error })
    return handle
  end

  local timeout_ms = tonumber(opts.timeout_ms) or M.DEFAULT_TIMEOUT_MS
  timeout_ms = math.max(1, math.min(timeout_ms, M.MAX_TIMEOUT_MS))

  if type(opts.runner) == "function" then
    local ok, returned = pcall(opts.runner, normalized, opts, function(raw)
      finish(raw)
    end)
    if not ok then
      finish({ exit_code = -1, stderr = "injected command runner failed" })
    else
      runner_handle = returned
    end
    vim.defer_fn(function()
      if completed then
        return
      end
      if runner_handle then
        local cancel = runner_handle
        if type(runner_handle) == "table" then
          cancel = runner_handle.cancel
        end
        if type(cancel) == "function" then
          pcall(cancel, runner_handle)
        end
      end
      finish({ timed_out = true, exit_code = -1, stderr = "operation timed out" })
    end, timeout_ms)
    return handle
  end

  local stdout_chunks = {}
  local stderr_chunks = {}
  local stdout_size = 0
  local stderr_size = 0

  local ok, started = pcall(vim.fn.jobstart, normalized, {
    cwd = opts.cwd,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      stdout_size = append_chunk(stdout_chunks, stdout_size, data, max_stdout)
    end,
    on_stderr = function(_, data)
      stderr_size = append_chunk(stderr_chunks, stderr_size, data, max_stderr)
    end,
    on_exit = function(_, exit_code)
      finish({
        stdout = table.concat(stdout_chunks),
        stderr = table.concat(stderr_chunks),
        exit_code = exit_code,
        stdout_truncated = stdout_size >= max_stdout,
        stderr_truncated = stderr_size >= max_stderr,
      })
    end,
  })

  if not ok or type(started) ~= "number" or started <= 0 then
    finish({ exit_code = -1, stderr = "unable to start external command" })
    return handle
  end
  job_id = started

  vim.defer_fn(function()
    if completed then
      return
    end
    local state = vim.fn.jobwait({ job_id }, 0)[1]
    if state == -1 then
      pcall(vim.fn.jobstop, job_id)
      finish({ timed_out = true, exit_code = -1, stderr = "operation timed out" })
    end
  end, timeout_ms)

  return handle
end

return M
