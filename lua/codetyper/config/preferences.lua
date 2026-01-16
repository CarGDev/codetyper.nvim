---@mod codetyper.preferences User preferences management
---@brief [[
--- Manages user preferences stored in .coder/preferences.json
--- Allows per-project configuration of plugin behavior.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")

---@class CoderPreferences
---@field auto_process boolean Whether to auto-process /@ @/ tags (default: nil = ask)
---@field asked_auto_process boolean Whether we've asked the user about auto_process

--- Default preferences
local defaults = {
  auto_process = nil, -- nil means "not yet decided"
  asked_auto_process = false,
}

--- Cached preferences per project
---@type table<string, CoderPreferences>
local cache = {}

--- Get the preferences file path for current project
---@return string
local function get_preferences_path()
  local cwd = vim.fn.getcwd()
  return cwd .. "/.coder/preferences.json"
end

--- Ensure .coder directory exists
local function ensure_coder_dir()
  local cwd = vim.fn.getcwd()
  local coder_dir = cwd .. "/.coder"
  if vim.fn.isdirectory(coder_dir) == 0 then
    vim.fn.mkdir(coder_dir, "p")
  end
end

--- Load preferences from file
---@return CoderPreferences
function M.load()
  local cwd = vim.fn.getcwd()

  -- Check cache first
  if cache[cwd] then
    return cache[cwd]
  end

  local path = get_preferences_path()
  local prefs = vim.deepcopy(defaults)

  if utils.file_exists(path) then
    local content = utils.read_file(path)
    if content then
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and decoded then
        -- Merge with defaults
        for k, v in pairs(decoded) do
          prefs[k] = v
        end
      end
    end
  end

  -- Cache it
  cache[cwd] = prefs
  return prefs
end

--- Save preferences to file
---@param prefs CoderPreferences
function M.save(prefs)
  local cwd = vim.fn.getcwd()
  ensure_coder_dir()

  local path = get_preferences_path()
  local ok, encoded = pcall(vim.json.encode, prefs)
  if ok then
    utils.write_file(path, encoded)
    -- Update cache
    cache[cwd] = prefs
  end
end

--- Get a specific preference
---@param key string
---@return any
function M.get(key)
  local prefs = M.load()
  return prefs[key]
end

--- Set a specific preference
---@param key string
---@param value any
function M.set(key, value)
  local prefs = M.load()
  prefs[key] = value
  M.save(prefs)
end

--- Check if auto-process is enabled
---@return boolean|nil Returns true/false if set, nil if not yet decided
function M.is_auto_process_enabled()
  return M.get("auto_process")
end

--- Set auto-process preference
---@param enabled boolean
function M.set_auto_process(enabled)
  M.set("auto_process", enabled)
  M.set("asked_auto_process", true)
end

--- Check if we've already asked the user about auto-process
---@return boolean
function M.has_asked_auto_process()
  return M.get("asked_auto_process") == true
end

--- Ask user about auto-process preference (shows floating window)
---@param callback function(enabled: boolean) Called with user's choice
function M.ask_auto_process_preference(callback)
  -- Check if already asked
  if M.has_asked_auto_process() then
    local enabled = M.is_auto_process_enabled()
    if enabled ~= nil then
      callback(enabled)
      return
    end
  end

  -- Create floating window to ask
  local width = 60
  local height = 7
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Codetyper Preferences ",
    title_pos = "center",
  })

  local lines = {
    "",
    "  How would you like to process /@ @/ prompt tags?",
    "",
    "  [a] Automatic - Process when you close the tag",
    "  [m] Manual    - Only process with :CoderProcess",
    "",
    "  Press 'a' or 'm' to choose (Esc to cancel)",
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Highlight
  local ns = vim.api.nvim_create_namespace("codetyper_prefs")
  vim.api.nvim_buf_add_highlight(buf, ns, "Title", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, "String", 3, 2, 5)
  vim.api.nvim_buf_add_highlight(buf, ns, "String", 4, 2, 5)

  local function close_and_callback(enabled)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if enabled ~= nil then
      M.set_auto_process(enabled)
      local mode = enabled and "automatic" or "manual"
      vim.notify("Codetyper: Set to " .. mode .. " mode (saved to .coder/preferences.json)", vim.log.levels.INFO)
    end
    if callback then
      callback(enabled)
    end
  end

  -- Keymaps
  local opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "a", function() close_and_callback(true) end, opts)
  vim.keymap.set("n", "A", function() close_and_callback(true) end, opts)
  vim.keymap.set("n", "m", function() close_and_callback(false) end, opts)
  vim.keymap.set("n", "M", function() close_and_callback(false) end, opts)
  vim.keymap.set("n", "<Esc>", function() close_and_callback(nil) end, opts)
  vim.keymap.set("n", "q", function() close_and_callback(nil) end, opts)
end

--- Clear cached preferences (useful when changing projects)
function M.clear_cache()
  cache = {}
end

--- Toggle auto-process mode
function M.toggle_auto_process()
  local current = M.is_auto_process_enabled()
  local new_value = not current
  M.set_auto_process(new_value)
  local mode = new_value and "automatic" or "manual"
  vim.notify("Codetyper: Switched to " .. mode .. " mode", vim.log.levels.INFO)
end

return M
