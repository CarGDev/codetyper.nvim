--- Bounded Streamable HTTP transport for the read-only Context7 MCP tools.

local local_cli = require("codetyper.core.agent.tools.local_cli")

local M = {}

M.DEFAULT_URL = "https://mcp.context7.com/mcp"
M.DEFAULT_PROTOCOL_VERSION = "2024-11-05"
M.DEFAULT_TIMEOUT_MS = 15000
M.MAX_TIMEOUT_MS = 120000
M.DEFAULT_MAX_BODY = 65536
M.MAX_BODY = 262144
M.MAX_REQUEST_BODY = 32768
M.CLIENT_NAME = "codetyper.nvim"
M.CLIENT_VERSION = "0.1"

local ALLOWED_METHODS = {
  initialize = true,
  ["notifications/initialized"] = true,
  ["tools/list"] = true,
  ["tools/call"] = true,
}

local ALLOWED_TOOLS = {
  ["resolve-library-id"] = true,
  ["query-docs"] = true,
}

local function bounded_text(value, limit)
  if type(value) ~= "string" then
    return ""
  end
  if #value <= limit then
    return value
  end
  if limit <= 16 then
    return value:sub(1, limit)
  end
  return value:sub(1, limit - 16) .. "\n...(truncated)"
end

local function body_limit(opts)
  opts = opts or {}
  local value = tonumber(opts.max_body) or M.DEFAULT_MAX_BODY
  return math.max(1, math.min(value, M.MAX_BODY))
end

local function valid_id(id)
  return (type(id) == "number" and id == math.floor(id)) or (type(id) == "string" and id ~= "")
end

local function header_value(headers, name)
  if type(headers) ~= "table" then
    return nil
  end
  local wanted = name:lower()
  for key, value in pairs(headers) do
    if type(key) == "string" and key:lower() == wanted then
      if type(value) == "table" then
        return value[#value]
      end
      return value
    end
  end
  return nil
end

local function parse_sse(body, opts)
  local data_lines = {}
  local function consume()
    if #data_lines == 0 then
      return nil, nil
    end
    local data = table.concat(data_lines, "\n")
    data_lines = {}
    if data == "[DONE]" then
      return nil, nil
    end
    local ok, value = pcall(vim.json.decode, data)
    if not ok then
      return nil, "malformed SSE JSON"
    end
    return value, nil
  end

  for line in (body .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    if line == "" then
      local value, err = consume()
      if value ~= nil or err then
        return value, err
      end
    elseif line:sub(1, 5) == "data:" then
      local value = line:sub(6)
      if value:sub(1, 1) == " " then
        value = value:sub(2)
      end
      table.insert(data_lines, value)
      if #table.concat(data_lines, "\n") > body_limit(opts) then
        return nil, "response body exceeds the configured bound"
      end
    end
  end

  local value, err = consume()
  if value ~= nil or err then
    return value, err
  end
  return nil, "empty SSE response"
end

--- Decode one bounded JSON or SSE MCP response without returning its raw body in errors.
function M.decode_response(body, headers, opts)
  local limit = body_limit(opts)
  if type(body) ~= "string" or body == "" then
    return nil, "empty response body"
  end
  if #body > limit then
    return nil, "response body exceeds the configured bound"
  end

  local content_type = tostring(header_value(headers, "content-type") or ""):lower()
  local looks_like_json = body:match("^%s*[%{%[]") ~= nil
  if
    not looks_like_json
    and (content_type:find("text/event%-stream", 1, false) or body:match("^%s*event:") or body:match("^%s*data:"))
  then
    return parse_sse(body, opts)
  end

  local ok, value = pcall(vim.json.decode, body)
  if not ok then
    return nil, "malformed JSON response"
  end
  return value, nil
end

function M.is_allowed_tool(name)
  return type(name) == "string" and ALLOWED_TOOLS[name] == true
end

function M.is_allowed_method(method)
  return type(method) == "string" and ALLOWED_METHODS[method] == true
end

function M.build_initialize(id)
  if not valid_id(id) then
    return nil, "MCP request id is required"
  end
  return {
    jsonrpc = "2.0",
    id = id,
    method = "initialize",
    params = {
      protocolVersion = M.DEFAULT_PROTOCOL_VERSION,
      capabilities = {},
      clientInfo = {
        name = M.CLIENT_NAME,
        version = M.CLIENT_VERSION,
      },
    },
  }
end

function M.build_initialized_notification()
  return {
    jsonrpc = "2.0",
    method = "notifications/initialized",
    params = {},
  }
end

function M.build_tools_list(id)
  if not valid_id(id) then
    return nil, "MCP request id is required"
  end
  return { jsonrpc = "2.0", id = id, method = "tools/list", params = {} }
end

local function copy_arguments(arguments)
  if type(arguments) ~= "table" then
    return nil, "Context7 tool arguments must be an object"
  end
  local copy = vim.deepcopy(arguments)
  if type(copy.query) ~= "string" or copy.query == "" then
    return nil, "Context7 query is required"
  end
  if copy.query:find("[%z\1-\31\127]") then
    return nil, "Context7 query contains invalid control characters"
  end
  return copy, nil
end

function M.build_tool_call(id, name, arguments)
  if not valid_id(id) then
    return nil, "MCP request id is required"
  end
  if not M.is_allowed_tool(name) then
    return nil, "Context7 tool is not allowlisted"
  end
  local normalized, args_error = copy_arguments(arguments)
  if not normalized then
    return nil, args_error
  end
  if name == "query-docs" then
    if type(normalized.libraryId) ~= "string" or normalized.libraryId == "" then
      return nil, "Context7 libraryId is required"
    end
    if normalized.libraryId:find("[%z\1-\31\127]") then
      return nil, "Context7 libraryId contains invalid control characters"
    end
  end
  return {
    jsonrpc = "2.0",
    id = id,
    method = "tools/call",
    params = { name = name, arguments = normalized },
  }
end

--- Build a message only for the fixed MCP protocol surface.
function M.build_message(id, method, params)
  if not M.is_allowed_method(method) then
    return nil, "MCP method is not allowlisted"
  end
  if method == "initialize" then
    return M.build_initialize(id)
  end
  if method == "notifications/initialized" then
    return M.build_initialized_notification()
  end
  if method == "tools/list" then
    return M.build_tools_list(id)
  end
  if method == "tools/call" then
    if type(params) ~= "table" then
      return nil, "MCP tool parameters are required"
    end
    return M.build_tool_call(id, params.name, params.arguments)
  end
  return nil, "MCP method is not allowlisted"
end

function M.session_id(headers)
  local value = header_value(headers, "Mcp-Session-Id")
  if type(value) ~= "string" or value == "" or value:find("[%z\1-\31\127]") then
    return nil
  end
  return value
end

function M.validate_url(url)
  if type(url) ~= "string" or url == "" then
    return nil, "Context7 MCP URL is required"
  end
  if url:find("[%z\1-\31\127]") or not url:match("^https://[^/]+/mcp$") then
    return nil, "Context7 MCP URL must be an HTTPS /mcp endpoint"
  end
  return url, nil
end

function M.headers(api_key, session)
  local headers = {
    ["Content-Type"] = "application/json",
    Accept = "application/json, text/event-stream",
  }
  if type(session) == "string" and session ~= "" then
    headers["Mcp-Session-Id"] = session
  end
  if type(api_key) == "string" and api_key ~= "" then
    headers.Authorization = "Bearer " .. api_key
  end
  return headers
end

local function append_output(chunks, size, value, limit)
  if type(value) == "table" then
    value = table.concat(value, "\n")
  elseif type(value) ~= "string" then
    value = ""
  end
  if value == "" or size >= limit then
    return size
  end
  local room = limit - size
  table.insert(chunks, value:sub(1, room))
  return size + math.min(#value, room)
end

local function parse_header_file(path, limit)
  local file = io.open(path, "r")
  if not file then
    return {}, 0
  end
  local content = file:read(limit + 1) or ""
  file:close()
  local headers = {}
  local status = 0
  for line in (content .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local code = line:match("^HTTP/[^%s]+%s+(%d%d%d)")
    if code then
      headers = {}
      status = tonumber(code) or 0
    else
      local name, value = line:match("^([^:]+):%s*(.*)$")
      if name and value then
        headers[name] = value
      end
    end
  end
  return headers, status
end

local function timeout_ms(value)
  local normalized = tonumber(value) or M.DEFAULT_TIMEOUT_MS
  return math.max(1, math.min(normalized, M.MAX_TIMEOUT_MS))
end

--- Execute one fixed POST request. Tests may inject a request function through the adapter.
function M.request(request, callback)
  if type(request) ~= "table" then
    callback({ status = 0, error = "invalid HTTP request" })
    return { cancel = function() end }
  end

  local url, url_error = M.validate_url(request.url)
  if not url then
    callback({ status = 0, error = url_error })
    return { cancel = function() end }
  end
  if type(request.body) ~= "string" or request.body == "" then
    callback({ status = 0, error = "empty HTTP request body" })
    return { cancel = function() end }
  end
  if #request.body > M.MAX_REQUEST_BODY then
    callback({ status = 0, error = "HTTP request body exceeds the configured bound" })
    return { cancel = function() end }
  end

  local body_path = os.tmpname()
  local header_path = os.tmpname()
  local body_file = io.open(body_path, "w")
  if not body_file then
    os.remove(body_path)
    os.remove(header_path)
    callback({ status = 0, error = "unable to create HTTP request body" })
    return { cancel = function() end }
  end
  body_file:write(request.body)
  body_file:close()

  local command = {
    "curl",
    "--silent",
    "--show-error",
    "--request",
    "POST",
    "--dump-header",
    header_path,
    "--data-binary",
    "@" .. body_path,
    "--max-time",
    tostring(math.ceil(timeout_ms(request.timeout_ms) / 1000)),
  }
  for name, value in pairs(request.headers or {}) do
    if type(name) == "string" and type(value) == "string" and value ~= "" then
      command[#command + 1] = "--header"
      command[#command + 1] = name .. ": " .. value
    end
  end
  command[#command + 1] = url

  local finished = false
  local job_id
  local stdout = {}
  local stderr = {}
  local stdout_size = 0
  local stderr_size = 0

  local function cleanup()
    os.remove(body_path)
    os.remove(header_path)
  end

  local function finish(value)
    if finished then
      return
    end
    finished = true
    cleanup()
    callback(value)
  end

  local handle = {}
  local function stop_job()
    if job_id and job_id > 0 then
      pcall(vim.fn.jobstop, job_id)
    end
  end

  function handle.cancel()
    if finished then
      return
    end
    stop_job()
    finish({ status = 0, cancelled = true, body = "", headers = {} })
  end

  local ok, started = pcall(vim.fn.jobstart, command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      stdout_size = append_output(stdout, stdout_size, data, M.DEFAULT_MAX_BODY)
    end,
    on_stderr = function(_, data)
      stderr_size = append_output(stderr, stderr_size, data, local_cli.MAX_ERROR)
    end,
    on_exit = function(_, code)
      if finished then
        return
      end
      local headers, status = parse_header_file(header_path, local_cli.DEFAULT_MAX_STDERR)
      if code ~= 0 then
        finish({ status = status, error = "Context7 HTTP transport failed", headers = headers, body = "" })
        return
      end
      finish({
        status = status,
        headers = headers,
        body = bounded_text(table.concat(stdout), M.DEFAULT_MAX_BODY),
        stderr = bounded_text(table.concat(stderr), local_cli.MAX_ERROR),
      })
    end,
  })
  if not ok or type(started) ~= "number" or started <= 0 then
    finish({ status = 0, error = "unable to start Context7 HTTP transport", headers = {}, body = "" })
    return handle
  end
  job_id = started

  vim.defer_fn(function()
    if finished then
      return
    end
    stop_job()
    finish({ status = 0, timed_out = true, body = "", headers = {} })
  end, timeout_ms(request.timeout_ms))

  return handle
end

M.parse_response = M.decode_response
M.parse_sse = parse_sse

return M
