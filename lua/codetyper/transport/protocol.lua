---@mod codetyper.transport.protocol JSON-RPC protocol for agent communication
---@brief [[
--- Defines the JSON-RPC protocol used for Lua <-> Python agent communication.
--- This module handles serialization, deserialization, and protocol validation.
---
--- Protocol Format:
---   Request:  {"jsonrpc": "2.0", "method": str, "params": dict, "id": int}
---   Response: {"jsonrpc": "2.0", "result": any, "id": int}
---   Error:    {"jsonrpc": "2.0", "error": {"code": int, "message": str}, "id": int}
---@brief ]]

local M = {}

---@class RPCRequest
---@field jsonrpc string Always "2.0"
---@field method string Method name
---@field params table Parameters
---@field id number|string Request ID

---@class RPCResponse
---@field jsonrpc string Always "2.0"
---@field result? any Result on success
---@field error? RPCError Error on failure
---@field id number|string|nil Request ID

---@class RPCError
---@field code number Error code
---@field message string Error message
---@field data? any Additional error data

-- Standard JSON-RPC error codes
M.ErrorCodes = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
  -- Custom server errors
  INTENT_CLASSIFICATION_FAILED = -32001,
  PLAN_CONSTRUCTION_FAILED = -32002,
  VALIDATION_FAILED = -32003,
  CONTEXT_ERROR = -32004,
  FORMATTING_ERROR = -32005,
}

-- Available methods
M.Methods = {
  CLASSIFY_INTENT = "classify_intent",
  BUILD_PLAN = "build_plan",
  VALIDATE_PLAN = "validate_plan",
  FORMAT_OUTPUT = "format_output",
  PING = "ping",
}

-- Intent types (must match Python IntentType enum)
M.IntentType = {
  ASK = "ask",
  CODE = "code",
  REFACTOR = "refactor",
  DOCUMENT = "document",
  FIX = "fix",
  EXPLAIN = "explain",
  TEST = "test",
  UNKNOWN = "unknown",
}

-- Action types (must match Python ActionType enum)
M.ActionType = {
  READ = "read",
  WRITE = "write",
  EDIT = "edit",
  DELETE = "delete",
  RENAME = "rename",
  CREATE_DIR = "create_dir",
}

-- Request ID counter
local request_id = 0

---Generate a new request ID
---@return number
local function next_id()
  request_id = request_id + 1
  return request_id
end

---Create a JSON-RPC request
---@param method string Method name
---@param params table Parameters
---@return RPCRequest
function M.make_request(method, params)
  return {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
    id = next_id(),
  }
end

---Serialize a request to JSON string
---@param request RPCRequest
---@return string
function M.serialize_request(request)
  local ok, json = pcall(vim.json.encode, request)
  if not ok then
    error("Failed to serialize request: " .. tostring(json))
  end
  return json
end

---Deserialize a response from JSON string
---@param raw string
---@return RPCResponse|nil response
---@return string|nil error
function M.deserialize_response(raw)
  local ok, response = pcall(vim.json.decode, raw)
  if not ok then
    return nil, "Failed to parse response: " .. tostring(response)
  end

  -- Validate response structure
  if type(response) ~= "table" then
    return nil, "Response is not an object"
  end

  if response.jsonrpc ~= "2.0" then
    return nil, "Invalid JSON-RPC version"
  end

  return response, nil
end

---Check if a response is an error
---@param response RPCResponse
---@return boolean
function M.is_error(response)
  return response.error ~= nil
end

---Extract error message from response
---@param response RPCResponse
---@return string
function M.get_error_message(response)
  if not response.error then
    return "Unknown error"
  end
  local msg = response.error.message or "Unknown error"
  if response.error.code then
    msg = string.format("[%d] %s", response.error.code, msg)
  end
  return msg
end

---Build IntentRequest params
---@param context string Buffer content and surrounding context
---@param prompt string User's prompt
---@param files? string[] Referenced file paths
---@return table
function M.build_intent_request(context, prompt, files)
  return {
    context = context,
    prompt = prompt,
    files = files or {},
  }
end

---Build PlanRequest params
---@param intent string Intent type
---@param context string Context
---@param files table<string, string> File path -> content map
---@return table
function M.build_plan_request(intent, context, files)
  return {
    intent = intent,
    context = context,
    files = files,
  }
end

---Build ValidationRequest params
---@param plan table Plan response from build_plan
---@param original_files table<string, string> Original file contents
---@return table
function M.build_validation_request(plan, original_files)
  return {
    plan = plan,
    original_files = original_files,
  }
end

---Build FormatRequest params
---@param format_type string "plan"|"diff"|"error"
---@param data table Data to format
---@return table
function M.build_format_request(format_type, data)
  return {
    type = format_type,
    data = data,
  }
end

---Parse IntentResponse from result
---@param result table Raw result from response
---@return table IntentResponse
function M.parse_intent_response(result)
  return {
    intent = result.intent,
    confidence = result.confidence,
    reasoning = result.reasoning,
    needs_clarification = result.needs_clarification or false,
    clarification_questions = result.clarification_questions or {},
  }
end

---Parse PlanResponse from result
---@param result table Raw result from response
---@return table PlanResponse
function M.parse_plan_response(result)
  local steps = {}
  for _, step in ipairs(result.steps or {}) do
    table.insert(steps, {
      id = step.id,
      action = step.action,
      target = step.target,
      params = step.params or {},
      depends_on = step.depends_on or {},
    })
  end

  local rollback_steps = {}
  for _, step in ipairs(result.rollback_steps or {}) do
    table.insert(rollback_steps, {
      id = step.id,
      action = step.action,
      target = step.target,
      params = step.params or {},
      depends_on = step.depends_on or {},
    })
  end

  return {
    steps = steps,
    needs_clarification = result.needs_clarification or false,
    clarification_questions = result.clarification_questions or {},
    rollback_steps = rollback_steps,
  }
end

---Parse ValidationResponse from result
---@param result table Raw result from response
---@return table ValidationResponse
function M.parse_validation_response(result)
  return {
    valid = result.valid,
    errors = result.errors or {},
    warnings = result.warnings or {},
  }
end

---Validate IntentRequest params
---@param params table
---@return boolean valid
---@return string|nil error
function M.validate_intent_request(params)
  if type(params.context) ~= "string" then
    return false, "Missing or invalid 'context' field"
  end
  if type(params.prompt) ~= "string" then
    return false, "Missing or invalid 'prompt' field"
  end
  if params.files and type(params.files) ~= "table" then
    return false, "'files' must be a list"
  end
  return true, nil
end

---Validate PlanRequest params
---@param params table
---@return boolean valid
---@return string|nil error
function M.validate_plan_request(params)
  if type(params.intent) ~= "string" then
    return false, "Missing or invalid 'intent' field"
  end
  if type(params.context) ~= "string" then
    return false, "Missing or invalid 'context' field"
  end
  if type(params.files) ~= "table" then
    return false, "Missing or invalid 'files' field"
  end
  return true, nil
end

return M
