local state = require("codetyper.state.state")

local M = {}

-- Get current codetyper configuration at call time
function M.get_config()
  local codetyper_loaded, codetyper = pcall(require, "codetyper")
  if codetyper_loaded and codetyper.get_config then
    return codetyper.get_config() or {}
  end
  local defaults = require("codetyper.constants.defaults")
  return defaults.get_defaults()
end

--- Clear all collected diff entries and reset index
function M.clear_diff_entries()
  state.entries = {}
  state.current_index = 1
end

--- Add a diff entry
---@param entry DiffEntry
function M.add_diff_entry(entry)
  table.insert(state.entries, entry)
end

--- Get all diff entries
---@return DiffEntry[]
function M.get_diff_entries()
  return state.entries
end

--- Get the number of diff entries
---@return number
function M.count_diff_entries()
  return #state.entries
end

function M.get_ui_dimensions()
  local ui = vim.api.nvim_list_uis()[1]
  if ui then
    return ui.width, ui.height
  end
  return vim.o.columns, vim.o.lines
end

return M
