---@mod codetyper.utils Utility functions for Codetyper.nvim

local M = {}

--- Get the project root directory
---@return string|nil Root directory path or nil if not found
function M.get_project_root()
  -- Try to find common root indicators
  local markers = { ".git", ".gitignore", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }

  local current = vim.fn.getcwd()

  for _, marker in ipairs(markers) do
    local found = vim.fn.findfile(marker, current .. ";")
    if found ~= "" then
      return vim.fn.fnamemodify(found, ":p:h")
    end
    found = vim.fn.finddir(marker, current .. ";")
    if found ~= "" then
      return vim.fn.fnamemodify(found, ":p:h")
    end
  end

  return current
end

--- Check if a file is a coder file
---@param filepath string File path to check
---@return boolean
function M.is_coder_file(filepath)
  return filepath:match("%.coder%.") ~= nil
end

--- Get the target file path from a coder file path
---@param coder_path string Path to the coder file
---@return string Target file path
function M.get_target_path(coder_path)
  -- Convert index.coder.ts -> index.ts
  return coder_path:gsub("%.coder%.", ".")
end

--- Get the coder file path from a target file path
---@param target_path string Path to the target file
---@return string Coder file path
function M.get_coder_path(target_path)
  -- Convert index.ts -> index.coder.ts
  local dir = vim.fn.fnamemodify(target_path, ":h")
  local name = vim.fn.fnamemodify(target_path, ":t:r")
  local ext = vim.fn.fnamemodify(target_path, ":e")

  if dir == "." then
    return name .. ".coder." .. ext
  end
  return dir .. "/" .. name .. ".coder." .. ext
end

--- Check if a file exists
---@param filepath string File path to check
---@return boolean
function M.file_exists(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil
end

--- Read file contents
---@param filepath string File path to read
---@return string|nil Contents or nil if error
function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  return content
end

--- Write content to file
---@param filepath string File path to write
---@param content string Content to write
---@return boolean Success status
function M.write_file(filepath, content)
  local file = io.open(filepath, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

--- Create directory if it doesn't exist
---@param dirpath string Directory path
---@return boolean Success status
function M.ensure_dir(dirpath)
  if vim.fn.isdirectory(dirpath) == 0 then
    return vim.fn.mkdir(dirpath, "p") == 1
  end
  return true
end

--- Notify user with proper formatting
---@param msg string Message to display
---@param level? number Vim log level (default: INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify("[Codetyper] " .. msg, level)
end

--- Get buffer filetype
---@param bufnr? number Buffer number (default: current)
---@return string Filetype
function M.get_filetype(bufnr)
  bufnr = bufnr or 0
  return vim.bo[bufnr].filetype
end

--- Escape pattern special characters
---@param str string String to escape
---@return string Escaped string
function M.escape_pattern(str)
  return str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

return M
