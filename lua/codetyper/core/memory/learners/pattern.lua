--- Brain Pattern Learner
--- Detects and learns code patterns

local types = require("codetyper.core.memory.types")

local M = {}

--- Detect if event contains a learnable pattern
---@param event LearnEvent Learning event
---@return boolean
function M.detect(event)
  if not event or not event.type then
    return false
  end

  local valid_types = {
    "code_completion",
    "file_indexed",
    "code_analyzed",
    "pattern_detected",
  }

  for _, t in ipairs(valid_types) do
    if event.type == t then
      return true
    end
  end

  return false
end

--- Extract pattern data from event
---@param event LearnEvent Learning event
---@return table|nil Extracted data
function M.extract(event)
  local data = event.data or {}

  -- Extract from code completion
  if event.type == "code_completion" then
    return {
      summary = "Code pattern: " .. (data.intent or "unknown"),
      detail = data.code or data.content or "",
      code = data.code,
      lang = data.language,
      file = event.file,
      function_name = data.function_name,
      symbols = data.symbols,
    }
  end

  -- Extract from file indexing
  if event.type == "file_indexed" then
    local patterns = {}

    -- Extract function patterns
    if data.functions then
      for _, func in ipairs(data.functions) do
        table.insert(patterns, {
          summary = "Function: " .. func.name,
          detail = func.signature or func.name,
          code = func.body,
          lang = data.language,
          file = event.file,
          function_name = func.name,
          lines = func.lines,
        })
      end
    end

    -- Extract class patterns
    if data.classes then
      for _, class in ipairs(data.classes) do
        table.insert(patterns, {
          summary = "Class: " .. class.name,
          detail = class.description or class.name,
          lang = data.language,
          file = event.file,
          symbols = { class.name },
        })
      end
    end

    return #patterns > 0 and patterns or nil
  end

  -- Extract from explicit pattern detection
  if event.type == "pattern_detected" then
    return {
      summary = data.name or "Unnamed pattern",
      detail = data.description or data.name or "",
      code = data.example,
      lang = data.language,
      file = event.file,
      symbols = data.symbols,
    }
  end

  return nil
end

--- Check if pattern should be learned
---@param data table Extracted data
---@return boolean
function M.should_learn(data)
  -- Skip if no meaningful content
  if not data.summary or data.summary == "" then
    return false
  end

  -- Skip very short patterns
  if data.detail and #data.detail < 10 then
    return false
  end

  -- Skip auto-generated patterns
  if data.summary:match("^%s*$") then
    return false
  end

  return true
end

--- Create node from pattern data
---@param data table Extracted data
---@return table Node creation params
function M.create_node_params(data)
  return {
    node_type = types.NODE_TYPES.PATTERN,
    content = {
      s = data.summary:sub(1, 200), -- Limit summary
      d = data.detail,
      code = data.code,
      lang = data.lang,
    },
    context = {
      f = data.file,
      fn = data.function_name,
      ln = data.lines,
      sym = data.symbols,
    },
    opts = {
      weight = 0.5,
      source = types.SOURCES.AUTO,
    },
  }
end

--- Find potentially related nodes
---@param data table Extracted data
---@param query_fn function Query function
---@return string[] Related node IDs
function M.find_related(data, query_fn)
  local related = {}

  -- Find nodes in same file
  if data.file then
    local file_nodes = query_fn({ file = data.file, limit = 5 })
    for _, node in ipairs(file_nodes) do
      table.insert(related, node.id)
    end
  end

  -- Find semantically similar
  if data.summary then
    local similar = query_fn({ query = data.summary, limit = 3 })
    for _, node in ipairs(similar) do
      if not vim.tbl_contains(related, node.id) then
        table.insert(related, node.id)
      end
    end
  end

  return related
end

return M
