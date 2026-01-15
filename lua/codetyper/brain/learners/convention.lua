--- Brain Convention Learner
--- Learns project conventions and coding standards

local types = require("codetyper.brain.types")

local M = {}

--- Detect if event contains convention info
---@param event LearnEvent Learning event
---@return boolean
function M.detect(event)
  local valid_types = {
    "convention_detected",
    "naming_pattern",
    "style_pattern",
    "project_structure",
    "config_change",
  }

  for _, t in ipairs(valid_types) do
    if event.type == t then
      return true
    end
  end

  return false
end

--- Extract convention data from event
---@param event LearnEvent Learning event
---@return table|nil Extracted data
function M.extract(event)
  local data = event.data or {}

  if event.type == "convention_detected" then
    return {
      summary = "Convention: " .. (data.name or "unnamed"),
      detail = data.description or data.name,
      rule = data.rule,
      examples = data.examples,
      category = data.category or "general",
      file = event.file,
    }
  end

  if event.type == "naming_pattern" then
    return {
      summary = "Naming: " .. (data.pattern_name or data.pattern),
      detail = "Naming convention: " .. (data.description or data.pattern),
      rule = data.pattern,
      examples = data.examples,
      category = "naming",
      scope = data.scope, -- function, variable, class, file
    }
  end

  if event.type == "style_pattern" then
    return {
      summary = "Style: " .. (data.name or "unnamed"),
      detail = data.description or "Code style pattern",
      rule = data.rule,
      examples = data.examples,
      category = "style",
      lang = data.language,
    }
  end

  if event.type == "project_structure" then
    return {
      summary = "Structure: " .. (data.pattern or "project layout"),
      detail = data.description or "Project structure convention",
      rule = data.rule,
      category = "structure",
      paths = data.paths,
    }
  end

  if event.type == "config_change" then
    return {
      summary = "Config: " .. (data.setting or "setting change"),
      detail = "Configuration: " .. (data.description or data.setting),
      before = data.before,
      after = data.after,
      category = "config",
      file = event.file,
    }
  end

  return nil
end

--- Check if convention should be learned
---@param data table Extracted data
---@return boolean
function M.should_learn(data)
  if not data.summary then
    return false
  end

  -- Skip very vague conventions
  if not data.detail or #data.detail < 5 then
    return false
  end

  return true
end

--- Create node from convention data
---@param data table Extracted data
---@return table Node creation params
function M.create_node_params(data)
  local detail = data.detail or ""

  -- Add examples if available
  if data.examples and #data.examples > 0 then
    detail = detail .. "\n\nExamples:"
    for _, ex in ipairs(data.examples) do
      detail = detail .. "\n- " .. tostring(ex)
    end
  end

  -- Add rule if available
  if data.rule then
    detail = detail .. "\n\nRule: " .. tostring(data.rule)
  end

  return {
    node_type = types.NODE_TYPES.CONVENTION,
    content = {
      s = data.summary:sub(1, 200),
      d = detail,
      lang = data.lang,
    },
    context = {
      f = data.file,
      sym = data.scope and { data.scope } or nil,
    },
    opts = {
      weight = 0.6,
      source = types.SOURCES.AUTO,
    },
  }
end

--- Find related conventions
---@param data table Extracted data
---@param query_fn function Query function
---@return string[] Related node IDs
function M.find_related(data, query_fn)
  local related = {}

  -- Find conventions in same category
  if data.category then
    local similar = query_fn({
      query = data.category,
      types = { types.NODE_TYPES.CONVENTION },
      limit = 5,
    })
    for _, node in ipairs(similar) do
      table.insert(related, node.id)
    end
  end

  -- Find patterns that follow this convention
  if data.rule then
    local patterns = query_fn({
      query = data.rule,
      types = { types.NODE_TYPES.PATTERN },
      limit = 3,
    })
    for _, node in ipairs(patterns) do
      if not vim.tbl_contains(related, node.id) then
        table.insert(related, node.id)
      end
    end
  end

  return related
end

--- Detect naming convention from symbol names
---@param symbols string[] Symbol names to analyze
---@return table|nil Detected convention
function M.detect_naming(symbols)
  if not symbols or #symbols < 3 then
    return nil
  end

  local patterns = {
    snake_case = 0,
    camelCase = 0,
    PascalCase = 0,
    SCREAMING_SNAKE = 0,
    kebab_case = 0,
  }

  for _, sym in ipairs(symbols) do
    if sym:match("^[a-z][a-z0-9_]*$") then
      patterns.snake_case = patterns.snake_case + 1
    elseif sym:match("^[a-z][a-zA-Z0-9]*$") then
      patterns.camelCase = patterns.camelCase + 1
    elseif sym:match("^[A-Z][a-zA-Z0-9]*$") then
      patterns.PascalCase = patterns.PascalCase + 1
    elseif sym:match("^[A-Z][A-Z0-9_]*$") then
      patterns.SCREAMING_SNAKE = patterns.SCREAMING_SNAKE + 1
    elseif sym:match("^[a-z][a-z0-9%-]*$") then
      patterns.kebab_case = patterns.kebab_case + 1
    end
  end

  -- Find dominant pattern
  local max_count = 0
  local dominant = nil

  for pattern, count in pairs(patterns) do
    if count > max_count then
      max_count = count
      dominant = pattern
    end
  end

  if dominant and max_count >= #symbols * 0.6 then
    return {
      pattern = dominant,
      confidence = max_count / #symbols,
      sample_size = #symbols,
    }
  end

  return nil
end

return M
