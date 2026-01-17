---@mod codetyper.agent.brain Long-term project memory
---@brief [[
--- Persistent knowledge about the project that accumulates over time.
--- Similar to semantic/long-term memory in the human brain.
--- Stored in .coder/brain/knowledge.json
---@brief ]]

local M = {}

---@class ProjectKnowledge
---@field structure table<string, string> Key directories and their purposes
---@field patterns table<string, string> Coding patterns and conventions
---@field key_files table<string, string> Important files and what they do
---@field architecture table<string, string> Architectural decisions
---@field testing string Testing approach and conventions
---@field dependencies string[] Key dependencies
---@field last_updated number Timestamp of last update

local utils = require("codetyper.support.utils")

---Get the brain file path
---@return string
local function get_brain_path()
  local brain_dir = vim.fn.getcwd() .. "/.coder/brain"
  vim.fn.mkdir(brain_dir, "p")
  return brain_dir .. "/knowledge.json"
end

---Load project knowledge from disk
---@return ProjectKnowledge
function M.load()
  local brain_path = get_brain_path()

  if vim.fn.filereadable(brain_path) == 1 then
    local content = table.concat(vim.fn.readfile(brain_path), "\n")
    local ok, knowledge = pcall(vim.json.decode, content)
    if ok then
      return knowledge
    end
  end

  -- Return empty knowledge structure
  return {
    structure = {},
    patterns = {},
    key_files = {},
    architecture = {},
    testing = "",
    dependencies = {},
    last_updated = 0,
  }
end

---Save project knowledge to disk
---@param knowledge ProjectKnowledge
function M.save(knowledge)
  knowledge.last_updated = os.time()

  local brain_path = get_brain_path()
  local content = vim.json.encode(knowledge)

  vim.fn.writefile(vim.split(content, "\n"), brain_path)
end

---Update project structure knowledge
---@param knowledge ProjectKnowledge
---@param directory string Directory path
---@param purpose string What this directory contains
function M.learn_structure(knowledge, directory, purpose)
  knowledge.structure[directory] = purpose
  M.save(knowledge)
end

---Update coding pattern knowledge
---@param knowledge ProjectKnowledge
---@param pattern_name string Pattern name (e.g., "error_handling", "module_structure")
---@param description string Pattern description
function M.learn_pattern(knowledge, pattern_name, description)
  knowledge.patterns[pattern_name] = description
  M.save(knowledge)
end

---Update key file knowledge
---@param knowledge ProjectKnowledge
---@param file_path string File path
---@param purpose string What this file does
function M.learn_key_file(knowledge, file_path, purpose)
  knowledge.key_files[file_path] = purpose
  M.save(knowledge)
end

---Update architectural knowledge
---@param knowledge ProjectKnowledge
---@param aspect string Architectural aspect (e.g., "state_management", "routing")
---@param description string How it works
function M.learn_architecture(knowledge, aspect, description)
  knowledge.architecture[aspect] = description
  M.save(knowledge)
end

---Update testing knowledge
---@param knowledge ProjectKnowledge
---@param description string Testing approach
function M.learn_testing(knowledge, description)
  knowledge.testing = description
  M.save(knowledge)
end

---Add dependency knowledge
---@param knowledge ProjectKnowledge
---@param dependency string Dependency name
function M.learn_dependency(knowledge, dependency)
  if not vim.tbl_contains(knowledge.dependencies, dependency) then
    table.insert(knowledge.dependencies, dependency)
    M.save(knowledge)
  end
end

---Format knowledge for LLM context
---@param knowledge ProjectKnowledge
---@return string formatted Formatted knowledge as markdown
function M.format_for_context(knowledge)
  local sections = {}

  table.insert(sections, "# Project Knowledge (Long-term Memory)")
  table.insert(sections, "")

  -- Structure
  if next(knowledge.structure) then
    table.insert(sections, "## Project Structure")
    for dir, purpose in pairs(knowledge.structure) do
      table.insert(sections, string.format("- `%s`: %s", dir, purpose))
    end
    table.insert(sections, "")
  end

  -- Key Files
  if next(knowledge.key_files) then
    table.insert(sections, "## Key Files")
    for file, purpose in pairs(knowledge.key_files) do
      table.insert(sections, string.format("- `%s`: %s", file, purpose))
    end
    table.insert(sections, "")
  end

  -- Patterns
  if next(knowledge.patterns) then
    table.insert(sections, "## Coding Patterns")
    for pattern, desc in pairs(knowledge.patterns) do
      table.insert(sections, string.format("- **%s**: %s", pattern, desc))
    end
    table.insert(sections, "")
  end

  -- Architecture
  if next(knowledge.architecture) then
    table.insert(sections, "## Architecture")
    for aspect, desc in pairs(knowledge.architecture) do
      table.insert(sections, string.format("- **%s**: %s", aspect, desc))
    end
    table.insert(sections, "")
  end

  -- Testing
  if knowledge.testing and knowledge.testing ~= "" then
    table.insert(sections, "## Testing")
    table.insert(sections, knowledge.testing)
    table.insert(sections, "")
  end

  -- Dependencies
  if #knowledge.dependencies > 0 then
    table.insert(sections, "## Key Dependencies")
    for _, dep in ipairs(knowledge.dependencies) do
      table.insert(sections, string.format("- %s", dep))
    end
    table.insert(sections, "")
  end

  return table.concat(sections, "\n")
end

---Parse knowledge updates from agent's discovery notes
---@param knowledge ProjectKnowledge
---@param discovery_text string Agent's discovery notes
function M.extract_and_learn(knowledge, discovery_text)
  -- Look for structured knowledge markers in the text
  -- Format: [LEARN:type:key] value

  for line in discovery_text:gmatch("[^\n]+") do
    local learn_type, key, value = line:match("%[LEARN:(%w+):([^%]]+)%]%s*(.+)")

    if learn_type and key and value then
      if learn_type == "structure" then
        M.learn_structure(knowledge, key, value)
      elseif learn_type == "pattern" then
        M.learn_pattern(knowledge, key, value)
      elseif learn_type == "file" then
        M.learn_key_file(knowledge, key, value)
      elseif learn_type == "architecture" then
        M.learn_architecture(knowledge, key, value)
      elseif learn_type == "testing" then
        M.learn_testing(knowledge, value)
      elseif learn_type == "dependency" then
        M.learn_dependency(knowledge, key)
      end
    end
  end
end

---Get summary of what agent knows
---@param knowledge ProjectKnowledge
---@return string summary Short summary of knowledge
function M.get_summary(knowledge)
  local parts = {}

  local struct_count = vim.tbl_count(knowledge.structure)
  local file_count = vim.tbl_count(knowledge.key_files)
  local pattern_count = vim.tbl_count(knowledge.patterns)

  if struct_count > 0 then
    table.insert(parts, string.format("%d directories", struct_count))
  end

  if file_count > 0 then
    table.insert(parts, string.format("%d key files", file_count))
  end

  if pattern_count > 0 then
    table.insert(parts, string.format("%d patterns", pattern_count))
  end

  if #parts == 0 then
    return "No project knowledge yet"
  end

  return "Knowledge: " .. table.concat(parts, ", ")
end

---Clear all knowledge (reset brain)
function M.reset()
  local brain_path = get_brain_path()
  if vim.fn.filereadable(brain_path) == 1 then
    os.remove(brain_path)
  end
end

return M
