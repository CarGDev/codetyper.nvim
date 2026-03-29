--- Architecture learner — extracts project structure patterns from tree.log
--- Teaches the LLM where different types of code belong
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Analyze project structure and extract architecture patterns
---@param tree_lines string[] Lines from tree.log
---@return table patterns { directories, conventions }
function M.analyze_tree(tree_lines)
  local dirs = {}
  local file_types = {}

  for _, line in ipairs(tree_lines) do
    -- Extract directory paths (lines with 📁 or ending with /)
    local dir = line:match("📁%s+(.+)") or line:match("│%s+(.+/)$")
    if dir then
      dir = dir:gsub("[│├└─ ]+", ""):gsub("^%s+", "")
      if dir ~= "" then
        table.insert(dirs, dir)
      end
    end

    -- Extract file paths with extensions
    local file = line:match("🌙%s+(.+%.%w+)") or line:match("📝%s+(.+%.%w+)")
    if file then
      file = file:gsub("[│├└─ ]+", ""):gsub("^%s+", "")
      local ext = file:match("%.(%w+)$")
      local dir_part = file:match("(.+)/[^/]+$") or ""
      if ext then
        if not file_types[dir_part] then
          file_types[dir_part] = {}
        end
        file_types[dir_part][ext] = (file_types[dir_part][ext] or 0) + 1
      end
    end
  end

  return {
    directories = dirs,
    file_types = file_types,
  }
end

--- Infer directory purposes from names and contents
---@param tree_analysis table From analyze_tree()
---@return table rules { dir_path = purpose_string }
function M.infer_conventions(tree_analysis)
  local rules = {}
  local known_patterns = {
    ["handler"] = "side-effect handlers (save, validate, normalize)",
    ["handlers"] = "side-effect handlers",
    ["utils"] = "pure utility functions",
    ["util"] = "pure utility functions",
    ["constants"] = "static data, configuration, enums",
    ["config"] = "user configuration and defaults",
    ["window"] = "UI windows (floating, split, panel)",
    ["core"] = "business logic modules",
    ["adapters"] = "framework-specific glue (Neovim API wrappers)",
    ["prompts"] = "LLM prompt templates",
    ["params"] = "parameter defaults for modules",
    ["state"] = "shared mutable state",
    ["support"] = "shared utilities and helpers",
    ["features"] = "user-facing features",
    ["inject"] = "code injection strategies",
    ["parser"] = "text parsing (prompts, code, tags)",
    ["agent"] = "agent system (executor, tools, loop)",
    ["providers"] = "LLM provider implementations",
    ["shared"] = "code shared across providers",
    ["selector"] = "provider selection logic",
    ["tiers"] = "model-tier prompt strategies",
  }

  for _, dir in ipairs(tree_analysis.directories) do
    local basename = dir:match("([^/]+)/?$") or dir
    basename = basename:gsub("/", "")
    if known_patterns[basename] then
      rules[dir] = known_patterns[basename]
    end
  end

  return rules
end

--- Build architecture context for LLM prompts
---@return string Architecture description for prompt inclusion
function M.get_architecture_context()
  local utils = require("codetyper.support.utils")
  local root = utils.get_project_root()
  local tree_path = root .. "/.codetyper/tree.log"

  if vim.fn.filereadable(tree_path) ~= 1 then
    return ""
  end

  local lines = vim.fn.readfile(tree_path)
  if not lines or #lines == 0 then
    return ""
  end

  local analysis = M.analyze_tree(lines)
  local conventions = M.infer_conventions(analysis)

  if vim.tbl_isempty(conventions) then
    return ""
  end

  local parts = { "\n\n--- Project Architecture ---" }
  parts[#parts + 1] = "Directory conventions (where different code belongs):"

  -- Sort by directory path for consistency
  local sorted_dirs = {}
  for dir, purpose in pairs(conventions) do
    table.insert(sorted_dirs, { dir = dir, purpose = purpose })
  end
  table.sort(sorted_dirs, function(a, b)
    return a.dir < b.dir
  end)

  for _, entry in ipairs(sorted_dirs) do
    parts[#parts + 1] = string.format("  %s/ → %s", entry.dir, entry.purpose)
  end

  flog.info("architecture", string.format("loaded %d directory conventions", #sorted_dirs)) -- TODO: remove after debugging

  return table.concat(parts, "\n")
end

--- Learn architecture to brain (called on tree update)
---@param tree_lines string[]
function M.learn(tree_lines)
  local brain_ok, brain = pcall(require, "codetyper.core.memory")
  if not brain_ok or not brain.is_initialized() then
    return
  end

  local analysis = M.analyze_tree(tree_lines)
  local conventions = M.infer_conventions(analysis)

  if vim.tbl_isempty(conventions) then
    return
  end

  local parts = {}
  for dir, purpose in pairs(conventions) do
    table.insert(parts, dir .. "/ → " .. purpose)
  end
  table.sort(parts)

  brain.learn({
    type = "architecture",
    summary = "Project directory conventions",
    detail = table.concat(parts, "\n"),
    weight = 0.9,
  })

  flog.info("architecture", "learned architecture patterns") -- TODO: remove after debugging
end

return M
