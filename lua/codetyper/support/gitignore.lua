---@mod codetyper.gitignore Gitignore management for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")

--- Patterns to add to .gitignore
local IGNORE_PATTERNS = {
  "*.coder.*",
  ".coder/",
}

--- Comment to identify codetyper entries
local CODER_COMMENT = "# Codetyper.nvim - AI coding partner files"

--- Check if pattern exists in gitignore content
---@param content string Gitignore content
---@param pattern string Pattern to check
---@return boolean
local function pattern_exists(content, pattern)
  local escaped = utils.escape_pattern(pattern)
  return content:match("\n" .. escaped .. "\n") ~= nil
    or content:match("^" .. escaped .. "\n") ~= nil
    or content:match("\n" .. escaped .. "$") ~= nil
    or content == pattern
end

--- Check if all patterns exist in gitignore content
---@param content string Gitignore content
---@return boolean, string[] All exist status and list of missing patterns
local function all_patterns_exist(content)
  local missing = {}
  for _, pattern in ipairs(IGNORE_PATTERNS) do
    if not pattern_exists(content, pattern) then
      table.insert(missing, pattern)
    end
  end
  return #missing == 0, missing
end

--- Get the path to .gitignore in project root
---@return string|nil Path to .gitignore or nil
function M.get_gitignore_path()
  local root = utils.get_project_root()
  if not root then
    return nil
  end
  return root .. "/.gitignore"
end

--- Check if coder files are already ignored
---@return boolean
function M.is_ignored()
  local gitignore_path = M.get_gitignore_path()
  if not gitignore_path then
    return false
  end

  local content = utils.read_file(gitignore_path)
  if not content then
    return false
  end

  local all_exist, _ = all_patterns_exist(content)
  return all_exist
end

--- Add coder patterns to .gitignore
---@return boolean Success status
function M.add_to_gitignore()
  local gitignore_path = M.get_gitignore_path()
  if not gitignore_path then
    utils.notify("Could not determine project root", vim.log.levels.WARN)
    return false
  end

  local content = utils.read_file(gitignore_path)
  local patterns_to_add = {}

  if content then
    -- File exists, check which patterns are missing
    local _, missing = all_patterns_exist(content)
    if #missing == 0 then
      return true -- All already ignored
    end
    patterns_to_add = missing
  else
    -- Create new .gitignore with all patterns
    content = ""
    patterns_to_add = IGNORE_PATTERNS
  end

  -- Build the patterns string
  local patterns_str = table.concat(patterns_to_add, "\n")

  if content == "" then
    -- New file
    content = CODER_COMMENT .. "\n" .. patterns_str .. "\n"
  else
    -- Append to existing
    local newline = content:sub(-1) == "\n" and "" or "\n"
    -- Check if comment already exists
    if not content:match(utils.escape_pattern(CODER_COMMENT)) then
      content = content .. newline .. "\n" .. CODER_COMMENT .. "\n" .. patterns_str .. "\n"
    else
      content = content .. newline .. patterns_str .. "\n"
    end
  end

  if utils.write_file(gitignore_path, content) then
    utils.notify("Added coder patterns to .gitignore")
    return true
  else
    utils.notify("Failed to update .gitignore", vim.log.levels.ERROR)
    return false
  end
end

--- Ensure coder files are in .gitignore (called on setup)
--- Only adds to .gitignore if in a git project (has .git/ folder)
--- Does NOT ask for permission - silently adds entries
---@param auto_gitignore? boolean Override auto_gitignore setting (default: true)
---@return boolean Success status
function M.ensure_ignored(auto_gitignore)
  -- Only add to gitignore if this is a git project
  if not utils.is_git_project() then
    return false -- Not a git project, skip
  end

  -- Default to true if not specified
  if auto_gitignore == nil then
    -- Try to get from config if available
    local ok, codetyper = pcall(require, "codetyper")
    if ok and codetyper.is_initialized and codetyper.is_initialized() then
      local config = codetyper.get_config()
      auto_gitignore = config and config.auto_gitignore
    else
      auto_gitignore = true -- Default to true
    end
  end

  if not auto_gitignore then
    return true
  end

  if M.is_ignored() then
    return true
  end

  -- Silently add to gitignore (no notifications unless there's an error)
  return M.add_to_gitignore_silent()
end

--- Add coder patterns to .gitignore silently (no notifications)
---@return boolean Success status
function M.add_to_gitignore_silent()
  local gitignore_path = M.get_gitignore_path()
  if not gitignore_path then
    return false
  end

  local content = utils.read_file(gitignore_path)
  local patterns_to_add = {}

  if content then
    local _, missing = all_patterns_exist(content)
    if #missing == 0 then
      return true
    end
    patterns_to_add = missing
  else
    content = ""
    patterns_to_add = IGNORE_PATTERNS
  end

  local patterns_str = table.concat(patterns_to_add, "\n")

  if content == "" then
    content = CODER_COMMENT .. "\n" .. patterns_str .. "\n"
  else
    local newline = content:sub(-1) == "\n" and "" or "\n"
    if not content:match(utils.escape_pattern(CODER_COMMENT)) then
      content = content .. newline .. "\n" .. CODER_COMMENT .. "\n" .. patterns_str .. "\n"
    else
      content = content .. newline .. patterns_str .. "\n"
    end
  end

  return utils.write_file(gitignore_path, content)
end

--- Remove coder patterns from .gitignore
---@return boolean Success status
function M.remove_from_gitignore()
  local gitignore_path = M.get_gitignore_path()
  if not gitignore_path then
    return false
  end

  local content = utils.read_file(gitignore_path)
  if not content then
    return false
  end

  -- Remove the comment and all patterns
  content = content:gsub(CODER_COMMENT .. "\n", "")
  for _, pattern in ipairs(IGNORE_PATTERNS) do
    content = content:gsub(utils.escape_pattern(pattern) .. "\n?", "")
  end

  -- Clean up extra newlines
  content = content:gsub("\n\n\n+", "\n\n")

  return utils.write_file(gitignore_path, content)
end

--- Get list of patterns being ignored
---@return string[] List of patterns
function M.get_ignore_patterns()
  return vim.deepcopy(IGNORE_PATTERNS)
end

--- Force update gitignore (manual trigger)
---@return boolean Success status
function M.force_update()
  local gitignore_path = M.get_gitignore_path()
  if not gitignore_path then
    utils.notify("Could not determine project root for .gitignore", vim.log.levels.WARN)
    return false
  end

  utils.notify("Updating .gitignore at: " .. gitignore_path)
  return M.add_to_gitignore()
end

return M
