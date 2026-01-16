---@mod codetyper.agent.diff_review Diff review UI for agent changes
---
--- Provides a lazygit-style window interface for reviewing all changes
--- made during an agent session.

local M = {}

local utils = require("codetyper.support.utils")
local prompts = require("codetyper.prompts.agent.diff")


---@class DiffEntry
---@field path string File path
---@field operation string "create"|"edit"|"delete"
---@field original string|nil Original content (nil for new files)
---@field modified string New/modified content
---@field approved boolean Whether change was approved
---@field applied boolean Whether change was applied

---@class DiffReviewState
---@field entries DiffEntry[] List of changes
---@field current_index number Currently selected entry
---@field list_buf number|nil File list buffer
---@field list_win number|nil File list window
---@field diff_buf number|nil Diff view buffer
---@field diff_win number|nil Diff view window
---@field is_open boolean Whether review UI is open

local state = {
  entries = {},
  current_index = 1,
  list_buf = nil,
  list_win = nil,
  diff_buf = nil,
  diff_win = nil,
  is_open = false,
}

--- Clear all collected diffs
function M.clear()
  state.entries = {}
  state.current_index = 1
end

--- Add a diff entry
---@param entry DiffEntry
function M.add(entry)
  table.insert(state.entries, entry)
end

--- Get all entries
---@return DiffEntry[]
function M.get_entries()
  return state.entries
end

--- Get entry count
---@return number
function M.count()
  return #state.entries
end

--- Generate unified diff between two strings
---@param original string|nil
---@param modified string
---@param filepath string
---@return string[]
local function generate_diff_lines(original, modified, filepath)
  local lines = {}
  local filename = vim.fn.fnamemodify(filepath, ":t")

  if not original then
    -- New file
    table.insert(lines, "--- /dev/null")
    table.insert(lines, "+++ b/" .. filename)
    table.insert(lines, "@@ -0,0 +1," .. #vim.split(modified, "\n") .. " @@")
    for _, line in ipairs(vim.split(modified, "\n")) do
      table.insert(lines, "+" .. line)
    end
  else
    -- Modified file - use vim's diff
    table.insert(lines, "--- a/" .. filename)
    table.insert(lines, "+++ b/" .. filename)

    local orig_lines = vim.split(original, "\n")
    local mod_lines = vim.split(modified, "\n")

    -- Simple diff: show removed and added lines
    local max_lines = math.max(#orig_lines, #mod_lines)
    local context_start = 1
    local in_change = false

    for i = 1, max_lines do
      local orig = orig_lines[i] or ""
      local mod = mod_lines[i] or ""

      if orig ~= mod then
        if not in_change then
          table.insert(lines, string.format("@@ -%d,%d +%d,%d @@",
            math.max(1, i - 2), math.min(5, #orig_lines - i + 3),
            math.max(1, i - 2), math.min(5, #mod_lines - i + 3)))
          in_change = true
        end
        if orig ~= "" then
          table.insert(lines, "-" .. orig)
        end
        if mod ~= "" then
          table.insert(lines, "+" .. mod)
        end
      else
        if in_change then
          table.insert(lines, " " .. orig)
          in_change = false
        end
      end
    end
  end

  return lines
end

--- Update the diff view for current entry
local function update_diff_view()
  if not state.diff_buf or not vim.api.nvim_buf_is_valid(state.diff_buf) then
    return
  end

  local entry = state.entries[state.current_index]
  local ui_prompts = prompts.review
  if not entry then
    vim.bo[state.diff_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, { ui_prompts.messages.no_changes_short })
    vim.bo[state.diff_buf].modifiable = false
    return
  end

  local lines = {}

  -- Header
  local status_icon = entry.applied and " " or (entry.approved and " " or " ")
  local op_icon = entry.operation == "create" and "+" or (entry.operation == "delete" and "-" or "~")
  local current_status = entry.applied and ui_prompts.status.applied
      or (entry.approved and ui_prompts.status.approved or ui_prompts.status.pending)

  table.insert(lines, string.format(ui_prompts.diff_header.top,
    status_icon, op_icon, vim.fn.fnamemodify(entry.path, ":t")))
  table.insert(lines, string.format(ui_prompts.diff_header.path, entry.path))
  table.insert(lines, string.format(ui_prompts.diff_header.op, entry.operation))
  table.insert(lines, string.format(ui_prompts.diff_header.status, current_status))
  table.insert(lines, ui_prompts.diff_header.bottom)
  table.insert(lines, "")

  -- Diff content
  local diff_lines = generate_diff_lines(entry.original, entry.modified, entry.path)
  for _, line in ipairs(diff_lines) do
    table.insert(lines, line)
  end

  vim.bo[state.diff_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, lines)
  vim.bo[state.diff_buf].modifiable = false
  vim.bo[state.diff_buf].filetype = "diff"
end

--- Update the file list
local function update_file_list()
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
    return
  end

  local ui_prompts = prompts.review
  local lines = {}
  table.insert(lines, string.format(ui_prompts.list_menu.top, #state.entries))
  for _, item in ipairs(ui_prompts.list_menu.items) do
    table.insert(lines, item)
  end
  table.insert(lines, ui_prompts.list_menu.bottom)
  table.insert(lines, "")

  for i, entry in ipairs(state.entries) do
    local prefix = (i == state.current_index) and "▶ " or "  "
    local status = entry.applied and "" or (entry.approved and "" or "○")
    local op = entry.operation == "create" and "[+]" or (entry.operation == "delete" and "[-]" or "[~]")
    local filename = vim.fn.fnamemodify(entry.path, ":t")

    table.insert(lines, string.format("%s%s %s %s", prefix, status, op, filename))
  end

  if #state.entries == 0 then
    table.insert(lines, ui_prompts.messages.no_changes)
  end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false

  -- Highlight current line
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    local target_line = 9 + state.current_index - 1
    if target_line <= vim.api.nvim_buf_line_count(state.list_buf) then
      vim.api.nvim_win_set_cursor(state.list_win, { target_line, 0 })
    end
  end
end

--- Navigate to next entry
function M.next()
  if state.current_index < #state.entries then
    state.current_index = state.current_index + 1
    update_file_list()
    update_diff_view()
  end
end

--- Navigate to previous entry
function M.prev()
  if state.current_index > 1 then
    state.current_index = state.current_index - 1
    update_file_list()
    update_diff_view()
  end
end

--- Approve current entry
function M.approve_current()
  local entry = state.entries[state.current_index]
  if entry and not entry.applied then
    entry.approved = true
    update_file_list()
    update_diff_view()
  end
end

--- Reject current entry
function M.reject_current()
  local entry = state.entries[state.current_index]
  if entry and not entry.applied then
    entry.approved = false
    update_file_list()
    update_diff_view()
  end
end

--- Approve all entries
function M.approve_all()
  for _, entry in ipairs(state.entries) do
    if not entry.applied then
      entry.approved = true
    end
  end
  update_file_list()
  update_diff_view()
end

--- Apply approved changes
function M.apply_approved()
  local applied_count = 0

  for _, entry in ipairs(state.entries) do
    if entry.approved and not entry.applied then
      if entry.operation == "create" or entry.operation == "edit" then
        local ok = utils.write_file(entry.path, entry.modified)
        if ok then
          entry.applied = true
          applied_count = applied_count + 1
        end
      elseif entry.operation == "delete" then
        local ok = os.remove(entry.path)
        if ok then
          entry.applied = true
          applied_count = applied_count + 1
        end
      end
    end
  end

  update_file_list()
  update_diff_view()

  if applied_count > 0 then
    utils.notify(string.format(prompts.review.messages.applied_count, applied_count))
  end

  return applied_count
end

--- Open the diff review UI
function M.open()
  if state.is_open then
    return
  end

  if #state.entries == 0 then
    utils.notify(prompts.review.messages.no_changes_short, vim.log.levels.INFO)
    return
  end

  -- Create list buffer
  state.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.list_buf].buftype = "nofile"
  vim.bo[state.list_buf].bufhidden = "wipe"
  vim.bo[state.list_buf].swapfile = false

  -- Create diff buffer
  state.diff_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.diff_buf].buftype = "nofile"
  vim.bo[state.diff_buf].bufhidden = "wipe"
  vim.bo[state.diff_buf].swapfile = false

  -- Create layout: list on left (30 cols), diff on right
  vim.cmd("tabnew")
  state.diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)

  vim.cmd("topleft vsplit")
  state.list_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.list_win, state.list_buf)
  vim.api.nvim_win_set_width(state.list_win, 35)

  -- Window options
  for _, win in ipairs({ state.list_win, state.diff_win }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
  end

  -- Set up keymaps for list buffer
  local list_opts = { buffer = state.list_buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", M.next, list_opts)
  vim.keymap.set("n", "k", M.prev, list_opts)
  vim.keymap.set("n", "<Down>", M.next, list_opts)
  vim.keymap.set("n", "<Up>", M.prev, list_opts)
  vim.keymap.set("n", "<CR>", function() vim.api.nvim_set_current_win(state.diff_win) end, list_opts)
  vim.keymap.set("n", "a", M.approve_current, list_opts)
  vim.keymap.set("n", "r", M.reject_current, list_opts)
  vim.keymap.set("n", "A", M.approve_all, list_opts)
  vim.keymap.set("n", "q", M.close, list_opts)
  vim.keymap.set("n", "<Esc>", M.close, list_opts)

  -- Set up keymaps for diff buffer
  local diff_opts = { buffer = state.diff_buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", M.next, diff_opts)
  vim.keymap.set("n", "k", M.prev, diff_opts)
  vim.keymap.set("n", "<Tab>", function() vim.api.nvim_set_current_win(state.list_win) end, diff_opts)
  vim.keymap.set("n", "a", M.approve_current, diff_opts)
  vim.keymap.set("n", "r", M.reject_current, diff_opts)
  vim.keymap.set("n", "A", M.approve_all, diff_opts)
  vim.keymap.set("n", "q", M.close, diff_opts)
  vim.keymap.set("n", "<Esc>", M.close, diff_opts)

  state.is_open = true
  state.current_index = 1

  -- Initial render
  update_file_list()
  update_diff_view()

  -- Focus list window
  vim.api.nvim_set_current_win(state.list_win)
end

--- Close the diff review UI
function M.close()
  if not state.is_open then
    return
  end

  -- Close the tab (which closes both windows)
  pcall(vim.cmd, "tabclose")

  state.list_buf = nil
  state.list_win = nil
  state.diff_buf = nil
  state.diff_win = nil
  state.is_open = false
end

--- Check if review UI is open
---@return boolean
function M.is_open()
  return state.is_open
end

return M
