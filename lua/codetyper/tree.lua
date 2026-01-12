---@mod codetyper.tree Project tree logging for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")

--- Name of the coder folder
local CODER_FOLDER = ".coder"

--- Name of the tree log file
local TREE_LOG_FILE = "tree.log"

--- Name of the settings file
local SETTINGS_FILE = "settings.json"

--- Default settings for the coder folder
local DEFAULT_SETTINGS = {
  ["editor.fontSize"] = 14,
  ["editor.tabSize"] = 2,
  ["files.autoSave"] = "afterDelay",
  ["files.autoSaveDelay"] = 1000,
  ["terminal.integrated.fontSize"] = 14,
  ["workbench.colorTheme"] = "Default Dark+",
}

--- Get the path to the .coder folder
---@return string|nil Path to .coder folder or nil
function M.get_coder_folder()
  local root = utils.get_project_root()
  if not root then
    return nil
  end
  return root .. "/" .. CODER_FOLDER
end

--- Get the path to the tree.log file
---@return string|nil Path to tree.log or nil
function M.get_tree_log_path()
  local coder_folder = M.get_coder_folder()
  if not coder_folder then
    return nil
  end
  return coder_folder .. "/" .. TREE_LOG_FILE
end

--- Get the path to the settings.json file
---@return string|nil Path to settings.json or nil
function M.get_settings_path()
  local coder_folder = M.get_coder_folder()
  if not coder_folder then
    return nil
  end
  return coder_folder .. "/" .. SETTINGS_FILE
end

--- Ensure settings.json exists with default settings
---@return boolean Success status
function M.ensure_settings()
  local settings_path = M.get_settings_path()
  if not settings_path then
    return false
  end

  -- Check if file already exists
  local stat = vim.loop.fs_stat(settings_path)
  if stat then
    return true -- File already exists, don't overwrite
  end

  -- Create settings file with defaults
  local json_content = vim.fn.json_encode(DEFAULT_SETTINGS)
  -- Pretty print the JSON
  local ok, pretty_json = pcall(function()
    return vim.fn.system({ "python3", "-m", "json.tool" }, json_content)
  end)

  if not ok or vim.v.shell_error ~= 0 then
    -- Fallback to simple formatting if python not available
    pretty_json = "{\n"
    local keys = vim.tbl_keys(DEFAULT_SETTINGS)
    table.sort(keys)
    for i, key in ipairs(keys) do
      local value = DEFAULT_SETTINGS[key]
      local value_str = type(value) == "string" and ('"' .. value .. '"') or tostring(value)
      pretty_json = pretty_json .. '  "' .. key .. '": ' .. value_str
      if i < #keys then
        pretty_json = pretty_json .. ","
      end
      pretty_json = pretty_json .. "\n"
    end
    pretty_json = pretty_json .. "}\n"
  end

  return utils.write_file(settings_path, pretty_json)
end

--- Ensure .coder folder exists
---@return boolean Success status
function M.ensure_coder_folder()
  local coder_folder = M.get_coder_folder()
  if not coder_folder then
    return false
  end
  return utils.ensure_dir(coder_folder)
end

--- Build tree structure recursively
---@param path string Directory path
---@param prefix string Prefix for tree lines
---@param ignore_patterns table Patterns to ignore
---@return string[] Tree lines
local function build_tree(path, prefix, ignore_patterns)
  local lines = {}
  local entries = {}

  -- Get directory entries
  local handle = vim.loop.fs_scandir(path)
  if not handle then
    return lines
  end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Check if should be ignored
    local should_ignore = false
    for _, pattern in ipairs(ignore_patterns) do
      if name:match(pattern) then
        should_ignore = true
        break
      end
    end

    if not should_ignore then
      table.insert(entries, { name = name, type = type })
    end
  end

  -- Sort entries (directories first, then alphabetically)
  table.sort(entries, function(a, b)
    if a.type == "directory" and b.type ~= "directory" then
      return true
    elseif a.type ~= "directory" and b.type == "directory" then
      return false
    end
    return a.name < b.name
  end)

  -- Build tree lines
  for i, entry in ipairs(entries) do
    local is_last = i == #entries
    local connector = is_last and "└── " or "├── "
    local child_prefix = is_last and "    " or "│   "

    local icon = ""
    if entry.type == "directory" then
      icon = "📁 "
    else
      -- File type icons
      local ext = entry.name:match("%.([^%.]+)$")
      local icons = {
        lua = "🌙 ",
        ts = "📘 ",
        tsx = "⚛️  ",
        js = "📒 ",
        jsx = "⚛️  ",
        py = "🐍 ",
        go = "🐹 ",
        rs = "🦀 ",
        md = "📝 ",
        json = "📋 ",
        yaml = "📋 ",
        yml = "📋 ",
        html = "🌐 ",
        css = "🎨 ",
        scss = "🎨 ",
      }
      icon = icons[ext] or "📄 "
    end

    table.insert(lines, prefix .. connector .. icon .. entry.name)

    if entry.type == "directory" then
      local child_path = path .. "/" .. entry.name
      local child_lines = build_tree(child_path, prefix .. child_prefix, ignore_patterns)
      for _, line in ipairs(child_lines) do
        table.insert(lines, line)
      end
    end
  end

  return lines
end

--- Generate project tree
---@return string Tree content
function M.generate_tree()
  local root = utils.get_project_root()
  if not root then
    return "-- Could not determine project root --"
  end

  local project_name = vim.fn.fnamemodify(root, ":t")
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")

  -- Patterns to ignore
  local ignore_patterns = {
    "^%.",           -- Hidden files/folders
    "^node_modules$",
    "^__pycache__$",
    "^%.git$",
    "^%.coder$",
    "^dist$",
    "^build$",
    "^target$",
    "^vendor$",
    "%.coder%.",     -- Coder files
  }

  local lines = {
    "# Project Tree: " .. project_name,
    "# Generated: " .. timestamp,
    "# By: Codetyper.nvim",
    "",
    "📦 " .. project_name,
  }

  local tree_lines = build_tree(root, "", ignore_patterns)
  for _, line in ipairs(tree_lines) do
    table.insert(lines, line)
  end

  table.insert(lines, "")
  table.insert(lines, "# Total files tracked by Codetyper")

  return table.concat(lines, "\n")
end

--- Update the tree.log file
---@return boolean Success status
function M.update_tree_log()
  -- Ensure .coder folder exists
  if not M.ensure_coder_folder() then
    return false
  end

  local tree_log_path = M.get_tree_log_path()
  if not tree_log_path then
    return false
  end

  local tree_content = M.generate_tree()

  if utils.write_file(tree_log_path, tree_content) then
    -- Silent update, no notification needed for every file change
    return true
  end

  return false
end

--- Cache to track initialized projects (by root path)
local initialized_projects = {}

--- Check if project is already initialized
---@param root string Project root path
---@return boolean
local function is_project_initialized(root)
  return initialized_projects[root] == true
end

--- Initialize tree logging (called on setup)
---@param force? boolean Force re-initialization even if cached
---@return boolean success
function M.setup(force)
  local coder_folder = M.get_coder_folder()
  if not coder_folder then
    return false
  end

  local root = utils.get_project_root()
  if not root then
    return false
  end

  -- Skip if already initialized (unless forced)
  if not force and is_project_initialized(root) then
    return true
  end

  -- Ensure .coder folder exists
  if not M.ensure_coder_folder() then
    utils.notify("Failed to create .coder folder", vim.log.levels.ERROR)
    return false
  end

  -- Create settings.json with defaults if it doesn't exist
  M.ensure_settings()

  -- Create initial tree log
  M.update_tree_log()

  -- Mark project as initialized
  initialized_projects[root] = true

  return true
end

--- Get file statistics from tree
---@return table Statistics { files: number, directories: number }
function M.get_stats()
  local root = utils.get_project_root()
  if not root then
    return { files = 0, directories = 0 }
  end

  local stats = { files = 0, directories = 0 }

  local function count_recursive(path)
    local handle = vim.loop.fs_scandir(path)
    if not handle then
      return
    end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      -- Skip hidden and special folders
      if not name:match("^%.") and name ~= "node_modules" and not name:match("%.coder%.") then
        if type == "directory" then
          stats.directories = stats.directories + 1
          count_recursive(path .. "/" .. name)
        else
          stats.files = stats.files + 1
        end
      end
    end
  end

  count_recursive(root)
  return stats
end

return M
