--- Canonical provider-agnostic registry for agent tools.

local local_cli = require("codetyper.core.agent.tools.local_cli")
local codegraph = require("codetyper.core.agent.tools.codegraph")
local tokensave = require("codetyper.core.agent.tools.tokensave")
local context7 = require("codetyper.core.agent.tools.context7")
local add_import = require("codetyper.core.agent.tools.add_import")
local ask_user = require("codetyper.window.ask_user")

local M = {}

local TOOL_DEFINITIONS = {
  {
    name = "codegraph_context",
    type = "function",
    description = "Read bounded context from an initialized CodeGraph project.",
    parameters = {
      type = "object",
      additionalProperties = false,
      properties = {
        query = { type = "string", minLength = 1, maxLength = 2000 },
        max_nodes = { type = "integer", minimum = 1, maximum = 100, default = 20 },
        no_code = { type = "boolean", default = false },
      },
      required = { "query" },
    },
  },
  {
    name = "tokensave_search",
    type = "function",
    description = "Search a current, branch-mapped TokenSave project index.",
    parameters = {
      type = "object",
      additionalProperties = false,
      properties = {
        query = { type = "string", minLength = 1, maxLength = 2000 },
        limit = { type = "integer", minimum = 1, maximum = 100, default = 10 },
      },
      required = { "query" },
    },
  },
  {
    name = "context7_resolve_library",
    type = "function",
    description = "Resolve a library identifier using the read-only Context7 MCP tool.",
    parameters = {
      type = "object",
      additionalProperties = false,
      properties = {
        query = { type = "string", minLength = 1, maxLength = 1000 },
      },
      required = { "query" },
    },
  },
  {
    name = "context7_query_docs",
    type = "function",
    description = "Query Context7 documentation using a resolved library identifier.",
    parameters = {
      type = "object",
      additionalProperties = false,
      properties = {
        library_id = { type = "string", minLength = 1, maxLength = 200 },
        query = { type = "string", minLength = 1, maxLength = 2000 },
      },
      required = { "library_id", "query" },
    },
  },
  {
    name = "ask_user",
    type = "function",
    description = "Ask the user a bounded question when the interactive unit is available.",
    parameters = {
      type = "object",
      additionalProperties = false,
      properties = {
        question = { type = "string", minLength = 1, maxLength = 1000 },
        options = {
          type = "array",
          minItems = 1,
          maxItems = 8,
          items = { type = "string", minLength = 1, maxLength = 200 },
        },
      },
      required = { "question", "options" },
    },
  },
  {
    name = "add_import",
    type = "function",
    description = "Plan one safe import declaration when the import unit is available.",
    parameters = {
      type = "object",
      additionalProperties = false,
      properties = {
        path = { type = "string", minLength = 1, maxLength = 1000 },
        statement = { type = "string", minLength = 1, maxLength = 500 },
      },
      required = { "path", "statement" },
    },
  },
}

local DEFINITIONS_BY_NAME = {}
for _, definition in ipairs(TOOL_DEFINITIONS) do
  DEFINITIONS_BY_NAME[definition.name] = definition
end

local function safe_error(value, fallback)
  return local_cli.safe_error(value, fallback)
end

local function string_value(value, field, max_length, allow_empty)
  if type(value) ~= "string" then
    return nil, field .. " must be a string"
  end
  local normalized = value:gsub("^%s+", ""):gsub("%s+$", "")
  if not allow_empty and normalized == "" then
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

local function validate_path(value)
  local path, err = string_value(value, "path", 1000, false)
  if not path then
    return nil, err
  end
  if path:match("^/") or path:match("^[A-Za-z]:[\\/]") then
    return nil, "path must be project-relative"
  end
  if path == "." or path:match("^%./") or path:find("%.%.[/\\]") or path:find("[/\\]%.%.[/\\]") then
    return nil, "path traversal is not allowed"
  end
  return path, nil
end

local function validate_options(options)
  if type(options) ~= "table" or #options < 1 or #options > 8 then
    return nil, "options must contain 1 to 8 strings"
  end
  local normalized = {}
  for index, option in ipairs(options) do
    local value, err = string_value(option, "option", 200, false)
    if not value then
      return nil, err
    end
    normalized[index] = value
  end
  for key in pairs(options) do
    if type(key) ~= "number" or key < 1 or key > #options or key ~= math.floor(key) then
      return nil, "options must be a contiguous list"
    end
  end
  return normalized, nil
end

local function validate_args(name, args)
  local definition = DEFINITIONS_BY_NAME[name]
  if not definition then
    return false, "unknown agent tool"
  end
  if type(args) ~= "table" then
    return false, "tool arguments must be an object"
  end

  for key in pairs(args) do
    if not definition.parameters.properties[key] then
      return false, "unexpected tool argument: " .. tostring(key)
    end
  end
  for _, key in ipairs(definition.parameters.required) do
    if args[key] == nil then
      return false, "missing required argument: " .. key
    end
  end

  local normalized = {}
  if name == "codegraph_context" then
    local query, query_error = string_value(args.query, "query", 2000, false)
    if not query or query:find("[%z\1-\31\127]") then
      return false, query_error or "query contains invalid control characters"
    end
    local max_nodes = args.max_nodes == nil and 20 or args.max_nodes
    if type(max_nodes) ~= "number" or max_nodes ~= math.floor(max_nodes) or max_nodes < 1 or max_nodes > 100 then
      return false, "max_nodes must be an integer from 1 to 100"
    end
    local no_code = args.no_code
    if no_code == nil then
      no_code = false
    end
    if type(no_code) ~= "boolean" then
      return false, "no_code must be boolean"
    end
    normalized = { query = query, max_nodes = max_nodes, no_code = no_code }
  elseif name == "tokensave_search" then
    local query, query_error = string_value(args.query, "query", 2000, false)
    if not query or query:find("[%z\1-\31\127]") then
      return false, query_error or "query contains invalid control characters"
    end
    local limit = args.limit == nil and 10 or args.limit
    if type(limit) ~= "number" or limit ~= math.floor(limit) or limit < 1 or limit > 100 then
      return false, "limit must be an integer from 1 to 100"
    end
    normalized = { query = query, limit = limit }
  elseif name == "context7_resolve_library" then
    local query, query_error = string_value(args.query, "query", 1000, false)
    if not query then
      return false, query_error
    end
    normalized = { query = query }
  elseif name == "context7_query_docs" then
    local library_id, library_error = string_value(args.library_id, "library_id", 200, false)
    local query, query_error = string_value(args.query, "query", 2000, false)
    if not library_id then
      return false, library_error
    end
    if not query then
      return false, query_error
    end
    normalized = { library_id = library_id, query = query }
  elseif name == "ask_user" then
    local question, question_error = string_value(args.question, "question", 1000, false)
    local options, options_error = validate_options(args.options)
    if not question then
      return false, question_error
    end
    if not options then
      return false, options_error
    end
    normalized = { question = question, options = options }
  elseif name == "add_import" then
    local path, path_error = validate_path(args.path)
    local statement, statement_error = string_value(args.statement, "statement", 500, false)
    if not path then
      return false, path_error
    end
    if not statement then
      return false, statement_error
    end
    if statement:find("[\r\n]") then
      return false, "statement must be a single line"
    end
    normalized = { path = path, statement = statement }
  end

  return true, normalized
end

local function unavailable(name)
  return {
    status = "unavailable",
    data = nil,
    error = safe_error(name .. " is not available in this apply unit", "tool is unavailable"),
    stale = true,
  }
end

local function normalize_result(value)
  if type(value) ~= "table" then
    return {
      status = "error",
      data = nil,
      error = "tool returned an invalid result",
      stale = true,
    }
  end
  local data = value.data
  if data ~= nil then
    local ok, encoded = pcall(vim.json.encode, data)
    if not ok or #encoded > 4000 then
      return {
        status = "error",
        data = nil,
        error = "tool result exceeds the 4000 character bound",
        stale = true,
      }
    end
  end
  local normalized = {
    status = type(value.status) == "string" and value.status or "error",
    data = value.data,
    error = value.error and safe_error(value.error, "tool request failed") or nil,
    stale = value.stale == true,
    metadata = value.metadata,
  }
  if value.index ~= nil then
    normalized.index = value.index
  end
  if value.option ~= nil then
    normalized.option = value.option
  end
  return normalized
end

local function invoke_adapter(name, args, callback, opts)
  opts = opts or {}
  local adapters = opts.adapters or {}
  local injected = adapters[name]
  if type(injected) == "function" then
    local ok, handle = pcall(injected, args, function(value)
      callback(normalize_result(value))
    end, opts)
    if not ok then
      callback({ status = "error", data = nil, error = "injected tool adapter failed", stale = true })
    end
    return handle or { cancel = function() end }
  end

  if name == "codegraph_context" then
    return codegraph.context(args, function(value)
      callback(normalize_result(value))
    end, opts)
  end
  if name == "tokensave_search" then
    return tokensave.search(args, function(value)
      callback(normalize_result(value))
    end, opts)
  end
  if name == "context7_resolve_library" then
    return context7.resolve(args, function(value)
      callback(normalize_result(value))
    end, opts)
  end
  if name == "context7_query_docs" then
    return context7.query(args, function(value)
      callback(normalize_result(value))
    end, opts)
  end
  if name == "ask_user" then
    return ask_user.request(args, function(value)
      callback(normalize_result(value))
    end, opts)
  end
  if name == "add_import" then
    local import_args = vim.deepcopy(args)
    import_args.root = opts.root
      or (opts.utils and opts.utils.get_project_root and opts.utils.get_project_root())
      or require("codetyper.support.utils").get_project_root()
    import_args.bufnr = opts.bufnr
    import_args.filetype = opts.filetype
    return add_import.call(import_args, function(value)
      callback(normalize_result(value))
    end, opts)
  end
  callback(unavailable(name))
  return { cancel = function() end }
end

local function copy_definition(definition)
  local copy = vim.deepcopy(definition)
  copy.schema = copy.parameters
  copy.inputSchema = copy.parameters
  return copy
end

--- Return exactly the six canonical schemas plus current availability metadata.
function M.list(opts)
  local availability = M.availability(opts)
  local entries = {}
  for _, definition in ipairs(TOOL_DEFINITIONS) do
    local entry = copy_definition(definition)
    local state = availability[definition.name]
    entry.available = state and state.available or false
    entry.stale = state and state.stale or true
    table.insert(entries, entry)
  end
  return entries
end

function M.get(name, opts)
  local definition = DEFINITIONS_BY_NAME[name]
  if not definition then
    return nil
  end
  local entry = copy_definition(definition)
  local state = M.availability(opts)[name]
  entry.available = state and state.available or false
  entry.stale = state and state.stale or true
  return entry
end

--- Return availability metadata without command or path details.
function M.availability(opts)
  opts = opts or {}
  local metadata = {}
  local codegraph_availability = codegraph.availability(opts)
  local tokensave_availability = tokensave.availability(opts)
  local codegraph_state = {
    name = "codegraph_context",
    available = codegraph_availability.available == true,
    stale = codegraph_availability.stale == true,
    error = codegraph_availability.error,
  }
  local tokensave_state = {
    name = "tokensave_search",
    available = tokensave_availability.available == true,
    stale = tokensave_availability.stale == true,
    error = tokensave_availability.error,
  }
  local context7_availability = context7.availability(opts)
  local context7_resolve = {
    name = "context7_resolve_library",
    available = context7_availability.available == true,
    stale = context7_availability.stale == true,
    error = context7_availability.error,
    source = context7_availability.source,
  }
  local context7_query = {
    name = "context7_query_docs",
    available = context7_availability.available == true,
    stale = context7_availability.stale == true,
    error = context7_availability.error,
    source = context7_availability.source,
  }
  local ask_user_availability = ask_user.availability(opts)
  local ask_user_state = {
    name = "ask_user",
    available = ask_user_availability.available == true,
    stale = ask_user_availability.stale == true,
    error = ask_user_availability.error,
  }
  local add_import_state = { name = "add_import", available = true, stale = false, error = nil }

  metadata.codegraph_context = codegraph_state
  metadata.tokensave_search = tokensave_state
  metadata.context7_resolve_library = context7_resolve
  metadata.context7_query_docs = context7_query
  metadata.ask_user = ask_user_state
  metadata.add_import = add_import_state
  for _, state in ipairs({
    codegraph_state,
    tokensave_state,
    context7_resolve,
    context7_query,
    ask_user_state,
    add_import_state,
  }) do
    table.insert(metadata, state)
  end
  return metadata
end

--- Validate a canonical tool call without executing it.
function M.validate(name, args)
  local valid, value = validate_args(name, args)
  if not valid then
    return false, safe_error(value, "invalid tool arguments")
  end
  return true, value
end

--- Dispatch one validated tool call and always return the shared result shape.
function M.dispatch(name, args, callback, opts)
  local valid, value = validate_args(name, args)
  if not valid then
    callback({ status = "error", data = nil, error = safe_error(value, "invalid tool arguments"), stale = false })
    return { cancel = function() end }
  end
  return invoke_adapter(name, value, callback, opts)
end

M.schemas = vim.deepcopy(TOOL_DEFINITIONS)
M.validate_args = M.validate
M.list_tools = M.list
M.get_tools = M.list
M.call = M.dispatch

return M
