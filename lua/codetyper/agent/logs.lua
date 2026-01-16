---@mod codetyper.agent.logs Real-time logging for agent operations
---
--- Captures and displays the agent's thinking process, token usage, and LLM info.

local M = {}

local params = require("codetyper.params.agent.logs")


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
  local icons = params.icons

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

--- Log warning
---@param message string
---@param data? table
function M.warning(message, data)
  M.log("warning", "WARN: " .. message, data)
end

--- Add log entry (compatibility function for scheduler)
--- Accepts {type = "info", message = "..."} format
---@param entry table Log entry with type and message
function M.add(entry)
  if entry.type == "clear" then
    M.clear()
    return
  end
  M.log(entry.type or "info", entry.message or "", entry.data)
end

--- Log thinking/reasoning step (Claude Code style)
---@param step string Description of what's happening
function M.thinking(step)
  M.log("thinking", step)
end

--- Log a reasoning/explanation message (shown prominently)
---@param message string The reasoning message
function M.reason(message)
  M.log("reason", message)
end

--- Log file read operation
---@param filepath string Path of file being read
---@param lines? number Number of lines read
function M.read(filepath, lines)
  local msg = string.format("Read(%s)", vim.fn.fnamemodify(filepath, ":~:."))
  if lines then
    msg = msg .. string.format("\n  ⎿  Read %d lines", lines)
  end
  M.log("action", msg)
end

--- Log explore/search operation
---@param description string What we're exploring
function M.explore(description)
  M.log("action", string.format("Explore(%s)", description))
end

--- Log explore done
---@param tool_uses number Number of tool uses
---@param tokens number Tokens used
---@param duration number Duration in seconds
function M.explore_done(tool_uses, tokens, duration)
  M.log("result", string.format("  ⎿  Done (%d tool uses · %.1fk tokens · %.1fs)", tool_uses, tokens / 1000, duration))
end

--- Log update/edit operation
---@param filepath string Path of file being edited
---@param added? number Lines added
---@param removed? number Lines removed
function M.update(filepath, added, removed)
  local msg = string.format("Update(%s)", vim.fn.fnamemodify(filepath, ":~:."))
  if added or removed then
    local parts = {}
    if added and added > 0 then
      table.insert(parts, string.format("Added %d lines", added))
    end
    if removed and removed > 0 then
      table.insert(parts, string.format("Removed %d lines", removed))
    end
    if #parts > 0 then
      msg = msg .. "\n  ⎿  " .. table.concat(parts, ", ")
    end
  end
  M.log("action", msg)
end

--- Log a task/step that's in progress
---@param task string Task name
---@param status string Status message (optional)
function M.task(task, status)
  local msg = task
  if status then
    msg = msg .. " " .. status
  end
  M.log("task", msg)
end

--- Log task completion
---@param next_task? string Next task (optional)
function M.task_done(next_task)
  local msg = "  ⎿  Done"
  if next_task then
    msg = msg .. "\n✶ " .. next_task
  end
  M.log("result", msg)
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
  -- Claude Code style formatting for thinking/action entries
  local thinking_types = params.thinking_types
  local is_thinking = vim.tbl_contains(thinking_types, entry.level)

  if is_thinking then
    local prefix = params.thinking_prefixes[entry.level] or "⏺"

    if prefix ~= "" then
      return prefix .. " " .. entry.message
    else
      return entry.message
    end
  end

  -- Traditional log format for other types
  local level_prefix = params.level_icons[entry.level] or "?"

  local base = string.format("[%s] %s %s", entry.timestamp, level_prefix, entry.message)

  -- If this is a response entry with raw_response, append the full response
  if entry.data and entry.data.raw_response then
    local response = entry.data.raw_response
    -- Add separator and the full response
    base = base .. "\n" .. string.rep("-", 40) .. "\n" .. response .. "\n" .. string.rep("-", 40)
  end

  return base
end

--- Format entry for display in chat (compact Claude Code style)
---@param entry LogEntry
---@return string|nil Formatted string or nil to skip
function M.format_for_chat(entry)
  -- Skip certain log types in chat view
  local skip_types = { "debug", "queue", "patch" }
  if vim.tbl_contains(skip_types, entry.level) then
    return nil
  end

  -- Claude Code style formatting
  local thinking_types = params.thinking_types
  if vim.tbl_contains(thinking_types, entry.level) then
    local prefix = params.thinking_prefixes[entry.level] or "⏺"

    if prefix ~= "" then
      return prefix .. " " .. entry.message
    else
      return entry.message
    end
  end

  -- Tool logs
  if entry.level == "tool" then
    return "⏺ " .. entry.message:gsub("^%[.-%] ", "")
  end

  -- Info/success
  if entry.level == "info" or entry.level == "success" then
    return "⏺ " .. entry.message
  end

  -- Errors
  if entry.level == "error" then
    return "⚠ " .. entry.message
  end

  -- Request/response (compact)
  if entry.level == "request" then
    return "⏺ " .. entry.message
  end
  if entry.level == "response" then
    return "  ⎿ " .. entry.message
  end

  return nil
end

--- Estimate token count for a string (rough approximation)
---@param text string
---@return number
function M.estimate_tokens(text)
  -- Rough estimate: ~4 characters per token for English text
  return math.ceil(#text / 4)
end

return M
