--- Context7 adapter with an mcphub-first read-only transport policy.

local local_cli = require("codetyper.core.agent.tools.local_cli")
local mcp = require("codetyper.core.agent.mcp")
local transport = require("codetyper.core.agent.tools.context7_transport")

local M = {}

M.DEFAULT_URL = transport.DEFAULT_URL
M.SERVER_NAME = "context7"
M.RESOLVE_TOOL = "resolve-library-id"
M.QUERY_TOOL = "query-docs"

local function safe_error(value, fallback, secret)
  local message = type(value) == "string" and value or ""
  if type(secret) == "string" and secret ~= "" and message:find(secret, 1, true) then
    message = "Context7 request failed"
  end
  return local_cli.safe_error(message, fallback)
end

local function result(status, data, error, stale, metadata, secret)
  if data ~= nil then
    local ok, encoded = pcall(vim.json.encode, data)
    if not ok or #encoded > 4000 then
      status = "error"
      data = nil
      error = "Context7 result exceeds the 4000 character bound"
      stale = true
    end
  end
  return {
    status = status,
    data = data,
    error = error and safe_error(error, "Context7 request failed", secret) or nil,
    stale = stale == true,
    metadata = metadata,
  }
end

local function text_value(value, field, max_length)
  if type(value) ~= "string" then
    return nil, field .. " must be a string"
  end
  local normalized = value:gsub("^%s+", ""):gsub("%s+$", "")
  if normalized == "" then
    return nil, field .. " must be non-empty text"
  end
  if normalized:find("[%z\1-\31\127]") then
    return nil, field .. " contains invalid control characters"
  end
  if #normalized > max_length then
    return nil, field .. " is too long"
  end
  return normalized, nil
end

local function validate_args(tool_name, args)
  if type(args) ~= "table" then
    return nil, "Context7 tool arguments must be an object"
  end
  if tool_name == M.RESOLVE_TOOL then
    for key in pairs(args) do
      if key ~= "query" then
        return nil, "unexpected Context7 argument: " .. tostring(key)
      end
    end
    local query, query_error = text_value(args.query, "query", 1000)
    if not query then
      return nil, query_error
    end
    return { query = query }, nil
  end
  if tool_name == M.QUERY_TOOL then
    for key in pairs(args) do
      if key ~= "libraryId" and key ~= "query" then
        return nil, "unexpected Context7 argument: " .. tostring(key)
      end
    end
    local library_id, library_error = text_value(args.libraryId, "libraryId", 200)
    local query, query_error = text_value(args.query, "query", 2000)
    if not library_id then
      return nil, library_error
    end
    if not query then
      return nil, query_error
    end
    return { libraryId = library_id, query = query }, nil
  end
  return nil, "Context7 tool is not allowlisted"
end

local function hub_state(seam)
  if type(seam) ~= "table" or type(seam.get_hub_state) ~= "function" then
    return { status = "absent" }
  end
  local ok, state = pcall(seam.get_hub_state)
  if not ok then
    return { status = "error", error = "mcphub state is unavailable" }
  end
  if type(state) == "string" then
    return { status = state }
  end
  if type(state) ~= "table" then
    return { status = "error", error = "mcphub state is invalid" }
  end
  local status = state.status
  if status ~= "ready" and status ~= "absent" and status ~= "not_ready" and status ~= "error" then
    status = "error"
  end
  return { status = status, error = state.error }
end

local function hub_seam(opts)
  if opts.mcp ~= nil then
    return opts.mcp
  end
  if type(opts.hub) ~= "table" then
    return mcp
  end
  local hub = opts.hub
  return {
    get_hub_state = function()
      if type(hub.is_ready) ~= "function" then
        return { status = "ready" }
      end
      local ok, ready = pcall(hub.is_ready, hub)
      if not ok then
        return { status = "error", error = "mcphub readiness check failed" }
      end
      return { status = ready == true and "ready" or "not_ready" }
    end,
    get_hub_tools = function()
      if type(hub.get_tools) ~= "function" then
        return nil, "mcphub tool listing is unavailable"
      end
      local ok, value = pcall(hub.get_tools, hub)
      if not ok then
        return nil, "mcphub tool listing failed"
      end
      return value
    end,
    call_tool = function(server, name, arguments, callback)
      if type(hub.call_tool) ~= "function" then
        error("mcphub tool execution is unavailable")
      end
      return hub:call_tool(server, name, arguments, { callback = callback, parse_response = true })
    end,
  }
end

local function hub_tools(seam)
  if type(seam) ~= "table" or type(seam.get_hub_tools) ~= "function" then
    return nil, "mcphub tools are unavailable"
  end
  local ok, tools, err = pcall(seam.get_hub_tools)
  if not ok then
    return nil, "mcphub tools are unavailable"
  end
  if type(tools) ~= "table" then
    return nil, err or "mcphub tools are unavailable"
  end
  return tools, nil
end

local function has_hub_tool(tools, name)
  for _, tool in ipairs(tools or {}) do
    if type(tool) == "table" and tool.name == name then
      local server = tool.server_name or tool.server or tool.serverName
      if server == nil or server == M.SERVER_NAME then
        return true
      end
    end
  end
  return false
end

local function extract_content(value)
  if type(value) == "string" then
    local ok, decoded = pcall(vim.json.decode, value)
    if ok then
      return extract_content(decoded)
    end
    return value, nil
  end
  if type(value) ~= "table" then
    return value, nil
  end
  if value.structuredContent ~= nil then
    return value.structuredContent, nil
  end
  if type(value.content) == "table" then
    local texts = {}
    for _, item in ipairs(value.content) do
      if type(item) == "table" and type(item.text) == "string" then
        table.insert(texts, item.text)
      end
    end
    if #texts == 1 then
      return extract_content(texts[1])
    end
    if #texts > 1 then
      local parsed = {}
      for _, text in ipairs(texts) do
        local item = extract_content(text)
        table.insert(parsed, item)
      end
      return parsed, nil
    end
  end
  return value, nil
end

local function normalize_tool_payload(payload)
  if type(payload) == "string" then
    return extract_content(payload)
  end
  if type(payload) ~= "table" then
    return nil, "Context7 returned an invalid MCP response"
  end
  if payload.error then
    local error_value = payload.error
    if type(error_value) == "table" then
      error_value = error_value.message or error_value.code
    end
    return nil, tostring(error_value or "Context7 MCP request failed")
  end
  local value = payload.result
  if type(value) == "table" and value.isError == true then
    return nil, "Context7 tool execution failed"
  end
  if value == nil then
    return nil, "Context7 MCP response has no result"
  end
  return extract_content(value)
end

local function metadata(source, operation, hub_status, extra)
  local value = {
    source = source,
    operation = operation,
  }
  if hub_status then
    value.hub_status = hub_status
  end
  for key, item in pairs(extra or {}) do
    if key ~= "url" and key ~= "headers" and key ~= "session" and key ~= "payload" then
      value[key] = item
    end
  end
  return value
end

local function get_api_key(opts)
  local provider = opts.api_key_provider or opts.get_api_key
  if type(provider) == "function" then
    local ok, value = pcall(provider)
    if not ok then
      return nil, "Context7 API key provider failed"
    end
    if value == nil or value == "" then
      return nil, nil
    end
    if type(value) ~= "string" or value:find("[%z\1-\31\127]") then
      return nil, "Context7 API key provider returned invalid data"
    end
    return value, nil
  end
  local value = vim.env.CONTEXT7_API_KEY
  if type(value) == "string" and value ~= "" then
    return value, nil
  end
  return nil, nil
end

local function requester_for(opts)
  if type(opts.transport) == "function" then
    return { request = opts.transport }, true
  end
  if type(opts.transport) == "table" and type(opts.transport.request) == "function" then
    return opts.transport, true
  end
  if type(opts.http) == "function" then
    return { request = opts.http }, true
  end
  if type(opts.http) == "table" and type(opts.http.request) == "function" then
    return opts.http, true
  end
  return transport, false
end

local function response_status(response)
  if type(response) ~= "table" then
    return 0
  end
  return tonumber(response.status or response.status_code) or 0
end

local function remote_request(requester, request, callback)
  local ok, handle = pcall(requester.request, request, callback)
  if not ok then
    callback({ status = 0, error = "Context7 HTTP request failed" })
    return { cancel = function() end }
  end
  return handle or { cancel = function() end }
end

local function run_remote(tool_name, arguments, callback, opts, hub_status)
  local api_key, key_error = get_api_key(opts)
  local requester, injected = requester_for(opts)
  if key_error then
    callback(result("error", nil, key_error, true, metadata("fallback", tool_name, hub_status), api_key))
    return { cancel = function() end }
  end
  if not injected and not api_key then
    callback(
      result(
        "unavailable",
        nil,
        "Context7 fallback credentials are unavailable",
        true,
        metadata("fallback", tool_name, hub_status)
      )
    )
    return { cancel = function() end }
  end

  local url, url_error = transport.validate_url(opts.url or M.DEFAULT_URL)
  if not url then
    callback(result("error", nil, url_error, true, metadata("fallback", tool_name, hub_status), api_key))
    return { cancel = function() end }
  end

  local timeout = tonumber(opts.timeout_ms) or transport.DEFAULT_TIMEOUT_MS
  timeout = math.max(1, math.min(timeout, transport.MAX_TIMEOUT_MS))
  local finished = false
  local current_handle
  local current_request = 0
  local session
  local next_id = 0

  local outer_handle = {}
  local function emit(value)
    if finished then
      return
    end
    finished = true
    callback(value)
  end

  function outer_handle.cancel()
    if finished then
      return
    end
    if current_handle and type(current_handle.cancel) == "function" then
      pcall(current_handle.cancel, current_handle)
    end
    emit(
      result(
        "cancelled",
        nil,
        "Context7 operation cancelled",
        true,
        metadata("fallback", tool_name, hub_status),
        api_key
      )
    )
  end

  local function send(payload, expect_response, on_success)
    if finished then
      return
    end
    current_request = current_request + 1
    local request_number = current_request
    local body_ok, body = pcall(vim.json.encode, payload)
    if not body_ok or type(body) ~= "string" then
      emit(
        result(
          "error",
          nil,
          "Context7 request could not be encoded",
          true,
          metadata("fallback", tool_name, hub_status),
          api_key
        )
      )
      return
    end
    local request = {
      method = "POST",
      url = url,
      headers = transport.headers(api_key, session),
      body = body,
      timeout_ms = timeout,
      max_body = opts.max_body,
    }
    local function complete(response)
      if finished or current_request ~= request_number then
        return
      end
      current_handle = nil
      response = type(response) == "table" and response or {}
      if response.cancelled then
        emit(
          result(
            "cancelled",
            nil,
            "Context7 operation cancelled",
            true,
            metadata("fallback", tool_name, hub_status),
            api_key
          )
        )
        return
      end
      if response.timed_out then
        emit(
          result(
            "error",
            nil,
            "Context7 operation timed out",
            true,
            metadata("fallback", tool_name, hub_status),
            api_key
          )
        )
        return
      end
      if response.error then
        emit(result("error", nil, response.error, true, metadata("fallback", tool_name, hub_status), api_key))
        return
      end
      local status = response_status(response)
      if status >= 400 then
        emit(
          result(
            "error",
            nil,
            "Context7 HTTP request failed",
            true,
            metadata("fallback", tool_name, hub_status, { http_status = status }),
            api_key
          )
        )
        return
      end
      if not expect_response and (response.body == nil or response.body == "") then
        on_success(nil, response)
        return
      end
      local decoded, decode_error =
        transport.decode_response(response.body, response.headers, { max_body = opts.max_body })
      if not decoded then
        emit(result("error", nil, decode_error, true, metadata("fallback", tool_name, hub_status), api_key))
        return
      end
      if decoded.error then
        local error_value = decoded.error
        if type(error_value) == "table" then
          error_value = error_value.message or error_value.code
        end
        emit(
          result(
            "error",
            nil,
            tostring(error_value or "Context7 MCP request failed"),
            true,
            metadata("fallback", tool_name, hub_status),
            api_key
          )
        )
        return
      end
      on_success(decoded, response)
    end

    local handle = remote_request(requester, request, complete)
    if current_request == request_number and not finished then
      current_handle = handle
    end
    vim.defer_fn(function()
      if finished or current_request ~= request_number then
        return
      end
      if current_handle and type(current_handle.cancel) == "function" then
        pcall(current_handle.cancel, current_handle)
      end
      emit(
        result("error", nil, "Context7 operation timed out", true, metadata("fallback", tool_name, hub_status), api_key)
      )
    end, timeout)
  end

  next_id = next_id + 1
  local initialize = transport.build_initialize(next_id)
  send(initialize, true, function(payload, response)
    if type(payload.result) ~= "table" then
      emit(
        result(
          "error",
          nil,
          "Context7 initialize response is invalid",
          true,
          metadata("fallback", tool_name, hub_status),
          api_key
        )
      )
      return
    end
    session = transport.session_id(response.headers)
    next_id = next_id + 1
    send(transport.build_initialized_notification(), false, function()
      next_id = next_id + 1
      send(transport.build_tools_list(next_id), true, function(list_payload)
        local list_result = list_payload.result
        local listed_tools = type(list_result) == "table" and list_result.tools or nil
        if type(listed_tools) ~= "table" or not has_hub_tool(listed_tools, tool_name) then
          emit(
            result(
              "unavailable",
              nil,
              "Context7 tool is unavailable from the remote server",
              true,
              metadata("fallback", tool_name, hub_status, { session_present = session ~= nil }),
              api_key
            )
          )
          return
        end
        next_id = next_id + 1
        local call_payload, call_error = transport.build_tool_call(next_id, tool_name, arguments)
        if not call_payload then
          emit(result("error", nil, call_error, false, metadata("fallback", tool_name, hub_status), api_key))
          return
        end
        send(call_payload, true, function(tool_payload)
          local data, tool_error = normalize_tool_payload(tool_payload)
          if tool_error then
            emit(result("error", nil, tool_error, true, metadata("fallback", tool_name, hub_status), api_key))
            return
          end
          emit(
            result(
              "available",
              data,
              nil,
              false,
              metadata("fallback", tool_name, hub_status, { session_present = session ~= nil }),
              api_key
            )
          )
        end)
      end)
    end)
  end)

  return outer_handle
end

local function run_hub(tool_name, arguments, callback, opts, state)
  local seam = hub_seam(opts)
  local tools, tools_error = hub_tools(seam)
  if not tools then
    callback(result("error", nil, tools_error, true, metadata("hub", tool_name, state.status)))
    return { cancel = function() end }, true
  end
  if not has_hub_tool(tools, tool_name) then
    return nil, false
  end
  if type(seam.call_tool) ~= "function" then
    callback(
      result("error", nil, "mcphub tool execution is unavailable", true, metadata("hub", tool_name, state.status))
    )
    return { cancel = function() end }, true
  end

  local complete = false
  local outer = {}
  local active
  local function emit(value)
    if complete then
      return
    end
    complete = true
    callback(value)
  end
  function outer.cancel()
    if complete then
      return
    end
    if active and type(active.cancel) == "function" then
      pcall(active.cancel, active)
    end
    emit(result("cancelled", nil, "Context7 operation cancelled", true, metadata("hub", tool_name, state.status)))
  end

  local ok, handle = pcall(seam.call_tool, M.SERVER_NAME, tool_name, arguments, function(response, err)
    if err then
      emit(
        result("error", nil, "mcphub Context7 tool execution failed", true, metadata("hub", tool_name, state.status))
      )
      return
    end
    local data, response_error = normalize_tool_payload(response)
    if response_error then
      emit(result("error", nil, response_error, true, metadata("hub", tool_name, state.status)))
      return
    end
    emit(result("available", data, nil, false, metadata("hub", tool_name, state.status)))
  end)
  if not ok then
    emit(result("error", nil, "mcphub tool execution failed", true, metadata("hub", tool_name, state.status)))
  else
    active = handle
  end
  return outer, true
end

local function execute(tool_name, arguments, callback, opts)
  opts = opts or {}
  local normalized, args_error = validate_args(tool_name, arguments)
  if not normalized then
    callback(result("error", nil, args_error, false, metadata("validation", tool_name, nil)))
    return { cancel = function() end }
  end

  local seam = hub_seam(opts)
  local state = hub_state(seam)
  if state.status == "ready" then
    local hub_handle, terminal = run_hub(tool_name, normalized, callback, opts, state)
    if terminal then
      return hub_handle
    end
  end
  return run_remote(tool_name, normalized, callback, opts, state.status)
end

function M.resolve(args, callback, opts)
  return execute(M.RESOLVE_TOOL, args or {}, callback, opts)
end

function M.query(args, callback, opts)
  args = args or {}
  local normalized = vim.deepcopy(args)
  if normalized.library_id ~= nil and normalized.libraryId == nil then
    normalized.libraryId = normalized.library_id
    normalized.library_id = nil
  end
  return execute(M.QUERY_TOOL, normalized, callback, opts)
end

M.resolve_library = M.resolve
M.query_docs = M.query
M.execute = execute

function M.validate(tool_name, args)
  local normalized, err = validate_args(tool_name, args)
  if not normalized then
    return false, safe_error(err, "invalid Context7 arguments")
  end
  return true, normalized
end

function M.availability(opts)
  opts = opts or {}
  local seam = hub_seam(opts)
  local state = hub_state(seam)
  if state.status == "ready" then
    local available_tools = hub_tools(seam)
    if
      type(available_tools) == "table"
      and (has_hub_tool(available_tools, M.RESOLVE_TOOL) or has_hub_tool(available_tools, M.QUERY_TOOL))
    then
      return { available = true, stale = false, source = "hub" }
    end
  end
  local api_key = get_api_key(opts)
  local injected = type(opts.transport) == "function"
    or type(opts.transport) == "table"
    or type(opts.http) == "function"
    or type(opts.http) == "table"
  if injected or api_key then
    return { available = true, stale = false, source = "fallback", hub_status = state.status }
  end
  return {
    available = false,
    stale = true,
    error = "Context7 fallback credentials are unavailable",
    source = "fallback",
    hub_status = state.status,
  }
end

M.normalize_result = result
M.normalize_tool_payload = normalize_tool_payload
M.call = execute

return M
