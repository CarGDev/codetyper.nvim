--- Brain Correction Learner
--- Learns from user corrections and edits

local types = require("codetyper.core.memory.types")

local M = {}

--- Detect if event is a correction
---@param event LearnEvent Learning event
---@return boolean
function M.detect(event)
  local valid_types = {
    "user_correction",
    "code_rejected",
    "code_modified",
    "suggestion_rejected",
  }

  for _, t in ipairs(valid_types) do
    if event.type == t then
      return true
    end
  end

  return false
end

--- Extract correction data from event
---@param event LearnEvent Learning event
---@return table|nil Extracted data
function M.extract(event)
  local data = event.data or {}

  if event.type == "user_correction" then
    return {
      summary = "Correction: " .. (data.error_type or "user edit"),
      detail = data.description or "User corrected the generated code",
      before = data.before,
      after = data.after,
      error_type = data.error_type,
      file = event.file,
      function_name = data.function_name,
      lines = data.lines,
    }
  end

  if event.type == "code_rejected" then
    return {
      summary = "Rejected: " .. (data.reason or "not accepted"),
      detail = data.description or "User rejected generated code",
      rejected_code = data.code,
      reason = data.reason,
      file = event.file,
      intent = data.intent,
    }
  end

  if event.type == "code_modified" then
    local changes = M.analyze_changes(data.before, data.after)
    return {
      summary = "Modified: " .. changes.summary,
      detail = changes.detail,
      before = data.before,
      after = data.after,
      change_type = changes.type,
      file = event.file,
      lines = data.lines,
    }
  end

  return nil
end

--- Analyze changes between before/after code
---@param before string Before code
---@param after string After code
---@return table Change analysis
function M.analyze_changes(before, after)
  before = before or ""
  after = after or ""

  local before_lines = vim.split(before, "\n")
  local after_lines = vim.split(after, "\n")

  local added = 0
  local removed = 0
  local modified = 0

  -- Simple line-based diff
  local max_lines = math.max(#before_lines, #after_lines)
  for i = 1, max_lines do
    local b = before_lines[i]
    local a = after_lines[i]

    if b == nil and a ~= nil then
      added = added + 1
    elseif b ~= nil and a == nil then
      removed = removed + 1
    elseif b ~= a then
      modified = modified + 1
    end
  end

  local change_type = "mixed"
  if added > 0 and removed == 0 and modified == 0 then
    change_type = "addition"
  elseif removed > 0 and added == 0 and modified == 0 then
    change_type = "deletion"
  elseif modified > 0 and added == 0 and removed == 0 then
    change_type = "modification"
  end

  return {
    type = change_type,
    summary = string.format("+%d -%d ~%d lines", added, removed, modified),
    detail = string.format("Added %d, removed %d, modified %d lines", added, removed, modified),
    stats = {
      added = added,
      removed = removed,
      modified = modified,
    },
  }
end

--- Check if correction should be learned
---@param data table Extracted data
---@return boolean
function M.should_learn(data)
  -- Always learn corrections - they're valuable
  if not data.summary then
    return false
  end

  -- Skip trivial changes
  if data.before and data.after then
    -- Skip if only whitespace changed
    local before_trimmed = data.before:gsub("%s+", "")
    local after_trimmed = data.after:gsub("%s+", "")
    if before_trimmed == after_trimmed then
      return false
    end
  end

  return true
end

--- Create node from correction data
---@param data table Extracted data
---@return table Node creation params
function M.create_node_params(data)
  local detail = data.detail or ""

  -- Include before/after in detail for learning
  if data.before and data.after then
    detail = detail .. "\n\nBefore:\n" .. data.before:sub(1, 500)
    detail = detail .. "\n\nAfter:\n" .. data.after:sub(1, 500)
  end

  return {
    node_type = types.NODE_TYPES.CORRECTION,
    content = {
      s = data.summary:sub(1, 200),
      d = detail,
      code = data.after or data.rejected_code,
      lang = data.lang,
    },
    context = {
      f = data.file,
      fn = data.function_name,
      ln = data.lines,
    },
    opts = {
      weight = 0.7, -- Corrections are valuable
      source = types.SOURCES.USER,
    },
  }
end

--- Find related nodes for corrections
---@param data table Extracted data
---@param query_fn function Query function
---@return string[] Related node IDs
function M.find_related(data, query_fn)
  local related = {}

  -- Find patterns that might be corrected
  if data.before then
    local similar = query_fn({
      query = data.before:sub(1, 100),
      types = { types.NODE_TYPES.PATTERN },
      limit = 3,
    })
    for _, node in ipairs(similar) do
      table.insert(related, node.id)
    end
  end

  -- Find other corrections in same file
  if data.file then
    local file_corrections = query_fn({
      file = data.file,
      types = { types.NODE_TYPES.CORRECTION },
      limit = 3,
    })
    for _, node in ipairs(file_corrections) do
      table.insert(related, node.id)
    end
  end

  return related
end

return M
