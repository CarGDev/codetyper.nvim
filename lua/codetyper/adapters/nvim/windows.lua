---@mod codetyper.window Window management for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")

---@type number|nil Current coder window ID
M._coder_win = nil

---@type number|nil Current target window ID
M._target_win = nil

---@type number|nil Current coder buffer ID
M._coder_buf = nil

---@type number|nil Current target buffer ID
M._target_buf = nil

--- Calculate window width based on configuration
---@param config CoderConfig Plugin configuration
---@return number Width in columns (minimum 30)
local function calculate_width(config)
  local width = config.window.width
  if width <= 1 then
    -- Percentage of total width (1/4 of screen with minimum 30)
    return math.max(math.floor(vim.o.columns * width), 30)
  end
  return math.max(math.floor(width), 30)
end

--- Open the coder split view
---@param target_path string Path to the target file
---@param coder_path string Path to the coder file
---@return boolean Success status
function M.open_split(target_path, coder_path)
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  -- Ensure coder file exists, create if not
  if not utils.file_exists(coder_path) then
    local dir = vim.fn.fnamemodify(coder_path, ":h")
    utils.ensure_dir(dir)
    utils.write_file(coder_path, "")
    
    -- Ensure gitignore is updated when creating a new coder file
    local gitignore = require("codetyper.support.gitignore")
    gitignore.ensure_ignored()
  end

  -- Store current window as target window
  M._target_win = vim.api.nvim_get_current_win()
  M._target_buf = vim.api.nvim_get_current_buf()

  -- Open target file if not already open
  if vim.fn.expand("%:p") ~= target_path then
    vim.cmd("edit " .. vim.fn.fnameescape(target_path))
    M._target_buf = vim.api.nvim_get_current_buf()
  end

  -- Calculate width
  local width = calculate_width(config)

  -- Create the coder split
  if config.window.position == "left" then
    vim.cmd("topleft vsplit " .. vim.fn.fnameescape(coder_path))
  else
    vim.cmd("botright vsplit " .. vim.fn.fnameescape(coder_path))
  end

  -- Store coder window reference
  M._coder_win = vim.api.nvim_get_current_win()
  M._coder_buf = vim.api.nvim_get_current_buf()

  -- Set coder window width
  vim.api.nvim_win_set_width(M._coder_win, width)

  -- Set up window options for coder window
  vim.wo[M._coder_win].number = true
  vim.wo[M._coder_win].relativenumber = true
  vim.wo[M._coder_win].wrap = true
  vim.wo[M._coder_win].signcolumn = "yes"

  -- Focus on target window (right side) by default
  if config.window.position == "left" then
    vim.api.nvim_set_current_win(M._target_win)
  end

  utils.notify("Coder view opened: " .. vim.fn.fnamemodify(coder_path, ":t"))

  return true
end

--- Close the coder split view
---@return boolean Success status
function M.close_split()
  if M._coder_win and vim.api.nvim_win_is_valid(M._coder_win) then
    vim.api.nvim_win_close(M._coder_win, false)
    M._coder_win = nil
    M._coder_buf = nil
    utils.notify("Coder view closed")
    return true
  end
  return false
end

--- Toggle the coder split view
---@param target_path? string Path to the target file
---@param coder_path? string Path to the coder file
function M.toggle_split(target_path, coder_path)
  if M._coder_win and vim.api.nvim_win_is_valid(M._coder_win) then
    M.close_split()
  else
    if target_path and coder_path then
      M.open_split(target_path, coder_path)
    else
      utils.notify("No file specified for coder view", vim.log.levels.WARN)
    end
  end
end

--- Check if coder view is currently open
---@return boolean
function M.is_open()
  return M._coder_win ~= nil and vim.api.nvim_win_is_valid(M._coder_win)
end

--- Get current coder window ID
---@return number|nil
function M.get_coder_win()
  return M._coder_win
end

--- Get current target window ID
---@return number|nil
function M.get_target_win()
  return M._target_win
end

--- Get current coder buffer ID
---@return number|nil
function M.get_coder_buf()
  return M._coder_buf
end

--- Get current target buffer ID
---@return number|nil
function M.get_target_buf()
  return M._target_buf
end

--- Focus on the coder window
function M.focus_coder()
  if M._coder_win and vim.api.nvim_win_is_valid(M._coder_win) then
    vim.api.nvim_set_current_win(M._coder_win)
  end
end

--- Focus on the target window
function M.focus_target()
  if M._target_win and vim.api.nvim_win_is_valid(M._target_win) then
    vim.api.nvim_set_current_win(M._target_win)
  end
end

--- Sync scroll between windows (optional feature)
---@param enable boolean Enable or disable sync scroll
function M.sync_scroll(enable)
  if not M.is_open() then
    return
  end

  local value = enable and "scrollbind" or "noscrollbind"
  vim.wo[M._coder_win][value] = enable
  vim.wo[M._target_win][value] = enable
end

return M
