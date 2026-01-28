---@mod codetyper.transport.agent_client Agent subprocess client
---@brief [[
--- Manages the Python agent subprocess and provides async communication.
--- Uses vim.loop (libuv) for non-blocking I/O.
---
--- The client:
--- - Spawns the Python agent as a subprocess
--- - Sends JSON-RPC requests via stdin
--- - Receives responses via stdout
--- - Handles process lifecycle (start, stop, restart)
--- - Queues requests when agent is busy
---@brief ]]

local M = {}
local protocol = require("codetyper.transport.protocol")

---@class AgentClient
---@field handle userdata|nil Process handle
---@field stdin userdata|nil Stdin pipe
---@field stdout userdata|nil Stdout pipe
---@field stderr userdata|nil Stderr pipe
---@field running boolean Is agent running
---@field pending table<number, function> Pending request callbacks by ID
---@field queue table[] Queued requests when busy
---@field buffer string Partial response buffer
---@field config AgentClientConfig Configuration

---@class AgentClientConfig
---@field python_path string Path to Python executable
---@field agent_module string Agent module path
---@field timeout number Request timeout in ms
---@field auto_restart boolean Auto-restart on crash
---@field max_retries number Max restart attempts
---@field on_error function|nil Error callback
---@field on_log function|nil Log callback

-- Default configuration
local DEFAULT_CONFIG = {
  python_path = "python3",
  agent_module = "agent.main",
  timeout = 30000,  -- 30 seconds
  auto_restart = true,
  max_retries = 3,
  on_error = nil,
  on_log = nil,
}

-- Singleton client instance
local client = nil

---Get the agent directory path
---@return string
local function get_agent_dir()
  -- Get the plugin directory
  -- Path: lua/codetyper/transport/agent_client.lua
  -- :h removes filename -> lua/codetyper/transport
  -- :h:h removes transport -> lua/codetyper
  -- :h:h:h removes codetyper -> lua
  -- :h:h:h:h removes lua -> plugin root
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h:h")
  return plugin_dir
end

---Log a message
---@param level string Log level
---@param msg string Message
local function log(level, msg)
  if client and client.config.on_log then
    client.config.on_log(level, msg)
  end
  -- Also log to Neovim
  if level == "error" then
    vim.schedule(function()
      vim.notify("[agent] " .. msg, vim.log.levels.ERROR)
    end)
  end
end

---Create a new agent client
---@param config? AgentClientConfig
---@return AgentClient
function M.new(config)
  local self = {
    handle = nil,
    stdin = nil,
    stdout = nil,
    stderr = nil,
    running = false,
    pending = {},
    queue = {},
    buffer = "",
    config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {}),
    restart_count = 0,
  }
  return self
end

---Initialize the singleton client
---@param config? AgentClientConfig
function M.setup(config)
  if client then
    M.stop()
  end
  client = M.new(config)
end

---Get the singleton client
---@return AgentClient|nil
function M.get_client()
  return client
end

---Start the agent subprocess
---@param cli? AgentClient Client instance (uses singleton if nil)
---@return boolean success
function M.start(cli)
  cli = cli or client

  -- Lazy initialization: create client if not initialized
  if not cli then
    M.setup()
    cli = client
  end

  if not cli then
    log("error", "Client not initialized")
    return false
  end

  if cli.running then
    return true
  end

  local uv = vim.loop

  -- Create pipes
  cli.stdin = uv.new_pipe(false)
  cli.stdout = uv.new_pipe(false)
  cli.stderr = uv.new_pipe(false)

  if not cli.stdin or not cli.stdout or not cli.stderr then
    log("error", "Failed to create pipes")
    return false
  end

  -- Build spawn options
  local agent_dir = get_agent_dir()

  -- Build environment: inherit current env and add our variables
  local env = {}
  for k, v in pairs(vim.fn.environ()) do
    table.insert(env, k .. "=" .. v)
  end
  table.insert(env, "PYTHONPATH=" .. agent_dir)
  table.insert(env, "PYTHONUNBUFFERED=1")

  local spawn_opts = {
    args = { "-m", cli.config.agent_module },
    stdio = { cli.stdin, cli.stdout, cli.stderr },
    cwd = agent_dir,
    env = env,
  }

  -- Spawn process
  local handle, pid = uv.spawn(cli.config.python_path, spawn_opts, function(code, signal)
    vim.schedule(function()
      M._on_exit(cli, code, signal)
    end)
  end)

  if not handle then
    log("error", "Failed to spawn agent: " .. tostring(pid))
    cli.stdin:close()
    cli.stdout:close()
    cli.stderr:close()
    return false
  end

  cli.handle = handle
  cli.running = true
  cli.buffer = ""

  -- Start reading stdout
  cli.stdout:read_start(function(err, data)
    if err then
      log("error", "Stdout read error: " .. tostring(err))
      return
    end
    if data then
      vim.schedule(function()
        M._on_stdout(cli, data)
      end)
    end
  end)

  -- Start reading stderr (for agent logs)
  cli.stderr:read_start(function(err, data)
    if err then
      return
    end
    if data then
      vim.schedule(function()
        M._on_stderr(cli, data)
      end)
    end
  end)

  log("info", "Agent started (pid: " .. tostring(pid or "?") .. ")")
  cli.restart_count = 0

  return true
end

---Stop the agent subprocess
---@param cli? AgentClient Client instance (uses singleton if nil)
function M.stop(cli)
  cli = cli or client
  if not cli then
    return
  end

  cli.running = false

  -- Cancel pending requests and their timers
  for id, pending in pairs(cli.pending) do
    if pending.timer then
      pending.timer:stop()
      pending.timer:close()
    end
    pending.callback(nil, "Agent stopped")
    cli.pending[id] = nil
  end

  -- Close pipes
  if cli.stdin then
    cli.stdin:close()
    cli.stdin = nil
  end
  if cli.stdout then
    cli.stdout:read_stop()
    cli.stdout:close()
    cli.stdout = nil
  end
  if cli.stderr then
    cli.stderr:read_stop()
    cli.stderr:close()
    cli.stderr = nil
  end

  -- Kill process
  if cli.handle then
    cli.handle:kill("sigterm")
    cli.handle:close()
    cli.handle = nil
  end

  log("info", "Agent stopped")
end

---Handle process exit
---@param cli AgentClient
---@param code number Exit code
---@param signal number Signal
function M._on_exit(cli, code, signal)
  cli.running = false

  log("info", string.format("Agent exited (code: %d, signal: %d)", code or 0, signal or 0))

  -- Cancel pending requests and their timers
  for id, pending in pairs(cli.pending) do
    if pending.timer then
      pending.timer:stop()
      pending.timer:close()
    end
    pending.callback(nil, "Agent process exited")
    cli.pending[id] = nil
  end

  -- Auto-restart if configured
  if cli.config.auto_restart and cli.restart_count < cli.config.max_retries then
    cli.restart_count = cli.restart_count + 1
    log("info", string.format("Auto-restarting agent (attempt %d/%d)", cli.restart_count, cli.config.max_retries))
    vim.defer_fn(function()
      M.start(cli)
      -- Process queued requests
      M._process_queue(cli)
    end, 1000)
  end
end

---Handle stdout data
---@param cli AgentClient
---@param data string
function M._on_stdout(cli, data)
  cli.buffer = cli.buffer .. data

  -- Process complete lines
  while true do
    local newline = cli.buffer:find("\n")
    if not newline then
      break
    end

    local line = cli.buffer:sub(1, newline - 1)
    cli.buffer = cli.buffer:sub(newline + 1)

    if line ~= "" then
      M._on_response(cli, line)
    end
  end
end

---Handle stderr data (agent logs)
---@param cli AgentClient
---@param data string
function M._on_stderr(cli, data)
  -- Forward to log callback - use info level so it's visible
  for line in data:gmatch("[^\n]+") do
    -- Check if it's an error message
    if line:match("Error") or line:match("error") or line:match("Traceback") or line:match("Exception") then
      log("error", "[agent] " .. line)
    else
      log("info", "[agent] " .. line)
    end
  end
end

---Handle a response line
---@param cli AgentClient
---@param line string
function M._on_response(cli, line)
  local response, err = protocol.deserialize_response(line)
  if err then
    log("error", "Failed to parse response: " .. err)
    return
  end

  -- Find pending request
  local id = response.id
  local pending = cli.pending[id]

  if not pending then
    log("warn", "Received response for unknown request: " .. tostring(id))
    return
  end

  -- Cancel timeout timer and remove from pending
  if pending.timer then
    pending.timer:stop()
    pending.timer:close()
  end
  cli.pending[id] = nil

  -- Call callback
  if protocol.is_error(response) then
    pending.callback(nil, protocol.get_error_message(response))
  else
    pending.callback(response.result, nil)
  end

  -- Process queue
  M._process_queue(cli)
end

---Process queued requests
---@param cli AgentClient
function M._process_queue(cli)
  if #cli.queue == 0 then
    return
  end

  if not cli.running then
    return
  end

  local queued = table.remove(cli.queue, 1)
  M._send_request(cli, queued.request, queued.callback)
end

---Send a request (internal)
---@param cli AgentClient
---@param request table
---@param callback function
function M._send_request(cli, request, callback)
  if not cli.running or not cli.stdin then
    callback(nil, "Agent not running")
    return
  end

  -- Set timeout timer
  local timeout_timer = vim.loop.new_timer()
  timeout_timer:start(cli.config.timeout, 0, function()
    timeout_timer:close()
    vim.schedule(function()
      local pending = cli.pending[request.id]
      if pending then
        cli.pending[request.id] = nil
        pending.callback(nil, "Request timed out")
      end
    end)
  end)

  -- Store callback and timer together so we can cancel timer on response
  cli.pending[request.id] = {
    callback = callback,
    timer = timeout_timer,
  }

  -- Send request
  local json = protocol.serialize_request(request)
  cli.stdin:write(json .. "\n")
end

---Send a request to the agent
---@param method string Method name
---@param params table Parameters
---@param callback fun(result: any, error: string|nil) Callback
---@param cli? AgentClient Client instance (uses singleton if nil)
function M.send_request(method, params, callback, cli)
  cli = cli or client

  -- Lazy initialization: create client if not initialized
  if not cli then
    M.setup()
    cli = client
  end

  if not cli then
    callback(nil, "Client not initialized")
    return
  end

  -- Build request
  local request = protocol.make_request(method, params)

  -- Start agent if needed
  if not cli.running then
    local started = M.start(cli)
    if not started then
      callback(nil, "Failed to start agent")
      return
    end
  end

  -- Queue if busy (too many pending requests)
  if vim.tbl_count(cli.pending) >= 10 then
    table.insert(cli.queue, { request = request, callback = callback })
    return
  end

  M._send_request(cli, request, callback)
end

---Send a synchronous request (blocking)
---@param method string Method name
---@param params table Parameters
---@param timeout? number Timeout in ms
---@param cli? AgentClient Client instance
---@return any|nil result
---@return string|nil error
function M.send_request_sync(method, params, timeout, cli)
  local co = coroutine.running()
  if not co then
    error("send_request_sync must be called from a coroutine")
  end

  local result, err

  M.send_request(method, params, function(r, e)
    result = r
    err = e
    coroutine.resume(co)
  end, cli)

  coroutine.yield()

  return result, err
end

-- ============================================================
-- High-level API methods
-- ============================================================

---Classify user intent
---@param context string Buffer context
---@param prompt string User prompt
---@param files? string[] Referenced files
---@param callback fun(result: table|nil, error: string|nil)
function M.classify_intent(context, prompt, files, callback)
  local params = protocol.build_intent_request(context, prompt, files)
  M.send_request(protocol.Methods.CLASSIFY_INTENT, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(protocol.parse_intent_response(result), nil)
  end)
end

---Build execution plan
---@param intent string Intent type
---@param context string Context
---@param files table<string, string> File contents
---@param callback fun(result: table|nil, error: string|nil)
function M.build_plan(intent, context, files, callback)
  local params = protocol.build_plan_request(intent, context, files)
  M.send_request(protocol.Methods.BUILD_PLAN, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(protocol.parse_plan_response(result), nil)
  end)
end

---Validate a plan
---@param plan table Plan from build_plan
---@param original_files table<string, string> Original file contents
---@param callback fun(result: table|nil, error: string|nil)
function M.validate_plan(plan, original_files, callback)
  local params = protocol.build_validation_request(plan, original_files)
  M.send_request(protocol.Methods.VALIDATE_PLAN, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(protocol.parse_validation_response(result), nil)
  end)
end

---Ping the agent (health check)
---@param callback fun(ok: boolean, error: string|nil)
function M.ping(callback)
  M.send_request(protocol.Methods.PING, {}, function(result, err)
    if err then
      callback(false, err)
      return
    end
    local ok = result and type(result) == "table" and result.status == "ok"
    callback(ok, nil)
  end)
end

---Check if agent is running
---@return boolean
function M.is_running()
  return client ~= nil and client.running
end

---Restart the agent
---@param callback? fun(ok: boolean, error: string|nil)
function M.restart(callback)
  M.stop()
  vim.defer_fn(function()
    local ok = M.start()
    if callback then
      callback(ok, ok and nil or "Failed to restart agent")
    end
  end, 500)
end

-- ============================================================
-- Memory Methods
-- ============================================================

---Get project root for memory operations
---@return string
local function get_project_root()
  -- Try to find git root, fallback to cwd
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
  if git_root and git_root ~= "" and not git_root:match("^fatal:") then
    return git_root
  end
  return vim.fn.getcwd()
end

---Learn from an event (edit, correction, approval, etc.)
---@param event_type string Type of event
---@param data table Event data
---@param callback fun(result: table|nil, error: string|nil)
function M.memory_learn(event_type, data, callback)
  local params = {
    project_root = get_project_root(),
    event_type = event_type,
    data = data,
  }
  M.send_request(protocol.Methods.MEMORY_LEARN, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(result, nil)
  end)
end

---Query the memory graph
---@param opts table Query options (node_type, content_pattern, limit)
---@param callback fun(result: table|nil, error: string|nil)
function M.memory_query(opts, callback)
  opts = opts or {}
  local params = {
    project_root = get_project_root(),
    node_type = opts.node_type,
    content_pattern = opts.content_pattern,
    limit = opts.limit or 20,
  }
  M.send_request(protocol.Methods.MEMORY_QUERY, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(result, nil)
  end)
end

---Get formatted memory context for LLM prompts
---@param context_type string Type of context (patterns, conventions, corrections, all)
---@param max_tokens? number Maximum tokens budget
---@param callback fun(result: table|nil, error: string|nil)
function M.memory_get_context(context_type, max_tokens, callback)
  local params = {
    project_root = get_project_root(),
    context_type = context_type or "all",
    max_tokens = max_tokens or 2000,
  }
  M.send_request(protocol.Methods.MEMORY_GET_CONTEXT, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(result, nil)
  end)
end

---Get memory statistics
---@param callback fun(result: table|nil, error: string|nil)
function M.memory_stats(callback)
  local params = {
    project_root = get_project_root(),
  }
  M.send_request(protocol.Methods.MEMORY_STATS, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(result, nil)
  end)
end

---Clear all memory
---@param callback fun(result: table|nil, error: string|nil)
function M.memory_clear(callback)
  local params = {
    project_root = get_project_root(),
  }
  M.send_request(protocol.Methods.MEMORY_CLEAR, params, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    callback(result, nil)
  end)
end

return M
