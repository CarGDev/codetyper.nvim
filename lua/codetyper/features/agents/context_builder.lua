---@mod codetyper.agent.context_builder Context builder for agent prompts
---
--- Builds rich context including project structure, memories, and conventions
--- to help the LLM understand the codebase.

local M = {}

local utils = require("codetyper.support.utils")
local params = require("codetyper.params.agents.context")

--- Get project structure as a tree string
---@param max_depth? number Maximum depth to traverse (default: 3)
---@param max_files? number Maximum files to show (default: 50)
---@return string Project tree
function M.get_project_structure(max_depth, max_files)
  max_depth = max_depth or 3
  max_files = max_files or 50

  local root = utils.get_project_root() or vim.fn.getcwd()
  local lines = { "PROJECT STRUCTURE:", root, "" }
  local file_count = 0

  -- Common ignore patterns
  local ignore_patterns = params.ignore_patterns

  local function should_ignore(name)
    for _, pattern in ipairs(ignore_patterns) do
      if name:match(pattern) then
        return true
      end
    end
    return false
  end

  local function traverse(path, depth, prefix)
    if depth > max_depth or file_count >= max_files then
      return
    end

    local entries = {}
    local handle = vim.loop.fs_scandir(path)
    if not handle then
      return
    end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end
      if not should_ignore(name) then
        table.insert(entries, { name = name, type = type })
      end
    end

    -- Sort: directories first, then alphabetically
    table.sort(entries, function(a, b)
      if a.type == "directory" and b.type ~= "directory" then
        return true
      elseif a.type ~= "directory" and b.type == "directory" then
        return false
      else
        return a.name < b.name
      end
    end)

    for i, entry in ipairs(entries) do
      if file_count >= max_files then
        table.insert(lines, prefix .. "... (truncated)")
        return
      end

      local is_last = (i == #entries)
      local branch = is_last and "└── " or "├── "
      local new_prefix = prefix .. (is_last and "    " or "│   ")

      local icon = entry.type == "directory" and "/" or ""
      table.insert(lines, prefix .. branch .. entry.name .. icon)
      file_count = file_count + 1

      if entry.type == "directory" then
        traverse(path .. "/" .. entry.name, depth + 1, new_prefix)
      end
    end
  end

  traverse(root, 1, "")

  if file_count >= max_files then
    table.insert(lines, "")
    table.insert(lines, "(Structure truncated at " .. max_files .. " entries)")
  end

  return table.concat(lines, "\n")
end

--- Get key files that are important for understanding the project
---@return table<string, string> Map of filename to description
function M.get_key_files()
  local root = utils.get_project_root() or vim.fn.getcwd()
  local key_files = {}

  local important_files = {
    ["package.json"] = "Node.js project config",
    ["Cargo.toml"] = "Rust project config",
    ["go.mod"] = "Go module config",
    ["pyproject.toml"] = "Python project config",
    ["setup.py"] = "Python setup config",
    ["Makefile"] = "Build configuration",
    ["CMakeLists.txt"] = "CMake config",
    [".gitignore"] = "Git ignore patterns",
    ["README.md"] = "Project documentation",
    ["init.lua"] = "Neovim plugin entry",
    ["plugin.lua"] = "Neovim plugin config",
  }

  for filename, desc in paparams.important_filesnd

  return key_files
end

--- Detect project type and language
---@return table { type: string, language: string, framework?: string }
function M.detect_project_type()
  local root = utils.get_project_root() or vim.fn.getcwd()

  local indicators = {
    ["package.json"] = { type = "node", language = "javascript/typescript" },
    ["Cargo.toml"] = { type = "rust", language = "rust" },
    ["go.mod"] = { type = "go", language = "go" },
    ["pyproject.toml"] = { type = "python", language = "python" },
    ["setup.py"] = { type = "python", language = "python" },
    ["Gemfile"] = { type = "ruby", language = "ruby" },
    ["pom.xml"] = { type = "maven", language = "java" },
    ["build.gradle"] = { type = "gradle", language = "java/kotlin" },
  }

  -- Check for Neovim plugin specifically
  if vim.fn.isdirectoparams.indicators   return info
    end
  end

  return { type = "unknown", language = "unknown" }
end

--- Get memories/patterns from the brain system
---@return string Formatted memories context
function M.get_memories_context()
  local ok_memory, memory = pcall(require, "codetyper.indexer.memory")
  if not ok_memory then
    return ""
  end

  local all = memory.get_all()
  if not all then
    return ""
  end

  local lines = {}

  -- Add patterns
  if all.patterns and next(all.patterns) then
    table.insert(lines, "LEARNED PATTERNS:")
    local count = 0
    for _, mem in pairs(all.patterns) do
      if count >= 5 then
        break
      end
      if mem.content then
        table.insert(lines, "  - " .. mem.content:sub(1, 100))
        count = count + 1
      end
    end
    table.insert(lines, "")
  end

  -- Add conventions
  if all.conventions and next(all.conventions) then
    table.insert(lines, "CODING CONVENTIONS:")
    local count = 0
    for _, mem in pairs(all.conventions) do
      if count >= 5 then
        break
      end
      if mem.content then
        table.insert(lines, "  - " .. mem.content:sub(1, 100))
        count = count + 1
      end
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

--- Build the full context for agent prompts
---@return string Full context string
function M.build_full_context()
  local sections = {}

  -- Project info
  local project_type = M.detect_project_type()
  table.insert(sections, string.format(
    "PROJECT INFO:\n  Type: %s\n  Language: %s%s\n",
    project_type.type,
    project_type.language,
    project_type.framework and ("\n  Framework: " .. project_type.framework) or ""
  ))

  -- Project structure
  local structure = M.get_project_structure(3, 40)
  table.insert(sections, structure)

  -- Key files
  local key_files = M.get_key_files()
  if next(key_files) then
    local key_lines = { "", "KEY FILES:" }
    for name, info in pairs(key_files) do
      table.insert(key_lines, string.format("  %s - %s", name, info.description))
    end
    table.insert(sections, table.concat(key_lines, "\n"))
  end

  -- Memories
  local memories = M.get_memories_context()
  if memories ~= "" then
    table.insert(sections, "\n" .. memories)
  end

  return table.concat(sections, "\n")
end

--- Get a compact context summary for token efficiency
---@return string Compact context
function M.build_compact_context()
  local root = utils.get_project_root() or vim.fn.getcwd()
  local project_type = M.detect_project_type()

  local lines = {
    "CONTEXT:",
    "  Root: " .. root,
    "  Type: " .. project_type.type .. " (" .. project_type.language .. ")",
  }

  -- Add main directories
  local main_dirs = {}
  local handle = vim.loop.fs_scandir(root)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end
      if type == "directory" and not name:match("^%.") and not name:match("node_modules") then
        table.insert(main_dirs, name .. "/")
      end
    end
  end

  if #main_dirs > 0 then
    table.sort(main_dirs)
    table.insert(lines, "  Main dirs: " .. table.concat(main_dirs, ", "))
  end

  return table.concat(lines, "\n")
end

return M
