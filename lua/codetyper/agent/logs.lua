---@mod codetyper.agent.logs Real-time logging for agent operations
---
--- Captures and displays the agent's thinking process, token usage, and LLM info.

local M = {}

---@class LogEntry
---@field timestamp string ISO timestamp
---@field level string "info" | "debug" | "request" | "response" | "tool" | "error"
---@field message string Log message
---@field data? table Optional structured data

---@class LogState
---@field entries LogEntry[] All log entries
---@field listeners table[] Functions to call when new entries are added
---@field total_prompt_tokens number Running total of prompt tokens
---@field total_response_tokens number Running total of response tokens

local state = {
  entries = {},
  listeners = {},
  total_prompt_tokens = 0,
  total_response_tokens = 0,
  current_provider = nil,
  current_model = nil,
}

--- Get current timestamp
---@return string
local function get_timestamp()
  return os.date("%H:%M:%S")
end

--- Add a log entry
---@param level string Log level
---@param message string Log message
---@param data? table Optional data
function M.log(level, message, data)
  local entry = {
    timestamp = get_timestamp(),
    level = level,
    message = message,
    data = data,
  }

  table.insert(state.entries, entry)

  -- Notify all listeners
  for _, listener in ipairs(state.listeners) do
    pcall(listener, entry)
  end
end

--- Log info message
---@param message string
---@param data? table
function M.info(message, data)
  M.log("info", message, data)
end

--- Log debug message
---@param message string
---@param data? table
function M.debug(message, data)
  M.log("debug", message, data)
end

--- Log API request
---@param provider string LLM provider
---@param model string Model name
---@param prompt_tokens? number Estimated prompt tokens
function M.request(provider, model, prompt_tokens)
  state.current_provider = provider
  state.current_model = model

  local msg = string.format("[%s] %s", provider:upper(), model)
  if prompt_tokens then
    msg = msg .. string.format(" | Prompt: ~%d tokens", prompt_tokens)
  end

  M.log("request", msg, {
    provider = provider,
    model = model,
    prompt_tokens = prompt_tokens,
  })
end

--- Log API response with token usage
---@param prompt_tokens number Tokens used in prompt
---@param response_tokens number Tokens in response
---@param stop_reason? string Why the response stopped
function M.response(prompt_tokens, response_tokens, stop_reason)
  state.total_prompt_tokens = state.total_prompt_tokens + prompt_tokens
  state.total_response_tokens = state.total_response_tokens + response_tokens

  local msg = string.format(
    "Tokens: %d in / %d out | Total: %d in / %d out",
    prompt_tokens,
    response_tokens,
    state.total_prompt_tokens,
    state.total_response_tokens
  )

  if stop_reason then
    msg = msg .. " | Stop: " .. stop_reason
  end

  M.log("response", msg, {
    prompt_tokens = prompt_tokens,
    response_tokens = response_tokens,
    total_prompt = state.total_prompt_tokens,
    total_response = state.total_response_tokens,
    stop_reason = stop_reason,
  })
end

--- Log tool execution
---@param tool_name string Name of the tool
---@param status string "start" | "success" | "error" | "approval"
---@param details? string Additional details
function M.tool(tool_name, status, details)
  local icons = {
    start = "->",
    success = "OK",
    error = "ERR",
    approval = "??",
    approved = "YES",
    rejected = "NO",
  }

  local msg = string.format("[%s] %s", icons[status] or status, tool_name)
  if details then
    msg = msg .. ": " .. details
  end

  M.log("tool", msg, {
    tool = tool_name,
    status = status,
    details = details,
  })
end

--- Log error
---@param message string
---@param data? table
function M.error(message, data)
  M.log("error", "ERROR: " .. message, data)
end

--- Log thinking/reasoning step
---@param step string Description of what's happening
function M.thinking(step)
  M.log("debug", "> " .. step)
end

--- Register a listener for new log entries
---@param callback fun(entry: LogEntry)
---@return number Listener ID for removal
function M.add_listener(callback)
  table.insert(state.listeners, callback)
  return #state.listeners
end

--- Remove a listener
---@param id number Listener ID
function M.remove_listener(id)
  if id > 0 and id <= #state.listeners then
    table.remove(state.listeners, id)
  end
end

--- Get all log entries
---@return LogEntry[]
function M.get_entries()
  return state.entries
end

--- Get token totals
---@return number, number prompt_tokens, response_tokens
function M.get_token_totals()
  return state.total_prompt_tokens, state.total_response_tokens
end

--- Get current provider info
---@return string?, string? provider, model
function M.get_provider_info()
  return state.current_provider, state.current_model
end

--- Clear all logs and reset counters
function M.clear()
  state.entries = {}
  state.total_prompt_tokens = 0
  state.total_response_tokens = 0
  state.current_provider = nil
  state.current_model = nil

  -- Notify listeners of clear
  for _, listener in ipairs(state.listeners) do
    pcall(listener, { level = "clear" })
  end
end

--- Format entry for display
---@param entry LogEntry
---@return string
function M.format_entry(entry)
  local level_prefix = ({
    info = "i",
    debug = ".",
    request = ">",
    response = "<",
    tool = "T",
    error = "!",
  })[entry.level] or "?"

  return string.format("[%s] %s %s", entry.timestamp, level_prefix, entry.message)
end

--- Estimate token count for a string (rough approximation)
---@param text string
---@return number
function M.estimate_tokens(text)
  -- Rough estimate: ~4 characters per token for English text
  return math.ceil(#text / 4)
end

return M
