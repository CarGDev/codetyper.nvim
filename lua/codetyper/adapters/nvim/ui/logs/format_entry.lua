local params = require("codetyper.params.agents.logs")

--- Format a log entry for display
---@param entry LogEntry
---@return string
local function format_entry(entry)
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

  local level_prefix = params.level_icons[entry.level] or "?"
  local base = string.format("[%s] %s %s", entry.timestamp, level_prefix, entry.message)

  if entry.data and entry.data.raw_response then
    local separator = string.rep("-", 40)
    base = base .. "\n" .. separator .. "\n" .. entry.data.raw_response .. "\n" .. separator
  end

  return base
end

return format_entry
