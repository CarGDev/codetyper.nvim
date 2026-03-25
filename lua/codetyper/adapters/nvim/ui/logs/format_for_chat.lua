local params = require("codetyper.params.agents.logs")

--- Format entry for display in chat (compact Claude Code style)
---@param entry LogEntry
---@return string|nil formatted Formatted string or nil to skip
local function format_for_chat(entry)
  local skip_types = { "debug", "queue", "patch" }
  if vim.tbl_contains(skip_types, entry.level) then
    return nil
  end

  local thinking_types = params.thinking_types
  if vim.tbl_contains(thinking_types, entry.level) then
    local prefix = params.thinking_prefixes[entry.level] or "⏺"
    if prefix ~= "" then
      return prefix .. " " .. entry.message
    else
      return entry.message
    end
  end

  if entry.level == "tool" then
    return "⏺ " .. entry.message:gsub("^%[.-%] ", "")
  end

  if entry.level == "info" or entry.level == "success" then
    return "⏺ " .. entry.message
  end

  if entry.level == "error" then
    return "⚠ " .. entry.message
  end

  if entry.level == "request" then
    return "⏺ " .. entry.message
  end

  if entry.level == "response" then
    return "  ⎿ " .. entry.message
  end

  return nil
end

return format_for_chat
