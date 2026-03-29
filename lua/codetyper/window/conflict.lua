local M = {}

local params = require("codetyper.params.agents.conflict")
local detect = require("codetyper.core.diff.detect")
local resolve = require("codetyper.core.diff.resolve")
local validate_after_accept = require("codetyper.handler.validate_after_accept")

local config = vim.deepcopy(params.config)
local HL_GROUPS = params.hl_groups
local MARKERS = params.markers

local NAMESPACE = vim.api.nvim_create_namespace("codetyper_conflict")
local HINT_NAMESPACE = vim.api.nvim_create_namespace("codetyper_conflict_hints")

--- Track buffers with active conflicts
local conflict_buffers = {}

--- Configure conflict behavior
---@param opts table Configuration options
function M.configure(opts)
  for k, v in pairs(opts) do
    if config[k] ~= nil then
      config[k] = v
    end
  end
end

--- Get current configuration
---@return table
function M.get_config()
  return vim.deepcopy(config)
end

--- Detect conflicts in a buffer
---@param bufnr number Buffer number
---@return table[] conflicts List of conflict positions
function M.detect_conflicts(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return detect.detect_conflicts(lines)
end

--- Get the conflict at the current cursor position
---@param bufnr number Buffer number
---@param cursor_line number Current line (1-indexed)
---@return table|nil conflict The conflict at cursor, or nil
function M.get_conflict_at_cursor(bufnr, cursor_line)
  local conflicts = M.detect_conflicts(bufnr)
  return detect.get_conflict_at_cursor(conflicts, cursor_line)
end

--- Auto-show menu for next conflict if enabled and conflicts remain
---@param bufnr number Buffer number
local function auto_show_next_conflict_menu(bufnr)
  if not config.auto_show_next_menu then
    return
  end

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local conflicts = M.detect_conflicts(bufnr)
    if #conflicts > 0 then
      local conflict = conflicts[1]
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(win) == bufnr then
        vim.api.nvim_win_set_cursor(win, { conflict.start_line, 0 })
        vim.cmd("normal! zz")
        M.show_floating_menu(bufnr)
      end
    end
  end)
end

--- Setup highlight groups
local function setup_highlights()
  vim.api.nvim_set_hl(0, HL_GROUPS.current, {
    bg = "#2d4a3e",
    default = true,
  })
  vim.api.nvim_set_hl(0, HL_GROUPS.current_label, {
    fg = "#98c379",
    bg = "#2d4a3e",
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, HL_GROUPS.incoming, {
    bg = "#2d3a4a",
    default = true,
  })
  vim.api.nvim_set_hl(0, HL_GROUPS.incoming_label, {
    fg = "#61afef",
    bg = "#2d3a4a",
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, HL_GROUPS.separator, {
    fg = "#5c6370",
    bg = "#3e4451",
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, HL_GROUPS.hint, {
    fg = "#5c6370",
    italic = true,
    default = true,
  })
end

--- Highlight conflicts in buffer using extmarks
---@param bufnr number Buffer number
---@param conflicts table[] Conflict positions
function M.highlight_conflicts(bufnr, conflicts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, HINT_NAMESPACE, 0, -1)

  for _, conflict in ipairs(conflicts) do
    vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, conflict.start_line - 1, 0, {
      end_row = conflict.start_line - 1,
      end_col = 0,
      line_hl_group = HL_GROUPS.current_label,
      priority = 100,
    })

    if conflict.current_start and conflict.current_end then
      for row = conflict.current_start, conflict.current_end do
        if row <= conflict.current_end then
          vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row - 1, 0, {
            end_row = row - 1,
            end_col = 0,
            line_hl_group = HL_GROUPS.current,
            priority = 90,
          })
        end
      end
    end

    if conflict.separator then
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, conflict.separator - 1, 0, {
        end_row = conflict.separator - 1,
        end_col = 0,
        line_hl_group = HL_GROUPS.separator,
        priority = 100,
      })
    end

    if conflict.incoming_start and conflict.incoming_end then
      for row = conflict.incoming_start, conflict.incoming_end do
        if row <= conflict.incoming_end then
          vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row - 1, 0, {
            end_row = row - 1,
            end_col = 0,
            line_hl_group = HL_GROUPS.incoming,
            priority = 90,
          })
        end
      end
    end

    if conflict.end_line then
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, conflict.end_line - 1, 0, {
        end_row = conflict.end_line - 1,
        end_col = 0,
        line_hl_group = HL_GROUPS.incoming_label,
        priority = 100,
      })
    end

    vim.api.nvim_buf_set_extmark(bufnr, HINT_NAMESPACE, conflict.start_line - 1, 0, {
      virt_text = {
        { "  [co]=ours [ct]=theirs [cb]=both [cn]=none [x/]x=nav", HL_GROUPS.hint },
      },
      virt_text_pos = "eol",
      priority = 50,
    })
  end
end

--- Accept "ours" - keep the original code
---@param bufnr number Buffer number
function M.accept_ours(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

  if not conflict then
    vim.notify("No conflict at cursor position", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local keep_lines = resolve.extract_ours(lines, conflict)

  vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, keep_lines)
  M.process(bufnr)

  vim.notify("Accepted CURRENT (original) code", vim.log.levels.INFO)
  auto_show_next_conflict_menu(bufnr)
end

--- Accept "theirs" - use the AI suggestion
---@param bufnr number Buffer number
function M.accept_theirs(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

  if not conflict then
    vim.notify("No conflict at cursor position", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local keep_lines = resolve.extract_theirs(lines, conflict)

  local insert_start = conflict.start_line
  local insert_end = insert_start + #keep_lines - 1

  vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, keep_lines)
  M.process(bufnr)

  vim.notify("Accepted INCOMING (AI suggestion) code", vim.log.levels.INFO)
  validate_after_accept(bufnr, insert_start, insert_end, "theirs")
  auto_show_next_conflict_menu(bufnr)
end

--- Accept "both" - keep both versions
---@param bufnr number Buffer number
function M.accept_both(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

  if not conflict then
    vim.notify("No conflict at cursor position", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local keep_lines = resolve.extract_both(lines, conflict)

  local insert_start = conflict.start_line
  local insert_end = insert_start + #keep_lines - 1

  vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, keep_lines)
  M.process(bufnr)

  vim.notify("Accepted BOTH (current + incoming) code", vim.log.levels.INFO)
  validate_after_accept(bufnr, insert_start, insert_end, "both")
  auto_show_next_conflict_menu(bufnr)
end

--- Accept "none" - delete both versions
---@param bufnr number Buffer number
function M.accept_none(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

  if not conflict then
    vim.notify("No conflict at cursor position", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, conflict.start_line - 1, conflict.end_line, false, {})
  M.process(bufnr)

  vim.notify("Deleted conflict (accepted NONE)", vim.log.levels.INFO)
  auto_show_next_conflict_menu(bufnr)
end

--- Navigate to the next conflict
---@param bufnr number Buffer number
---@return boolean found Whether a conflict was found
function M.goto_next(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local conflicts = M.detect_conflicts(bufnr)

  for _, conflict in ipairs(conflicts) do
    if conflict.start_line > cursor_line then
      vim.api.nvim_win_set_cursor(0, { conflict.start_line, 0 })
      vim.cmd("normal! zz")
      return true
    end
  end

  if #conflicts > 0 then
    vim.api.nvim_win_set_cursor(0, { conflicts[1].start_line, 0 })
    vim.cmd("normal! zz")
    vim.notify("Wrapped to first conflict", vim.log.levels.INFO)
    return true
  end

  vim.notify("No more conflicts", vim.log.levels.INFO)
  return false
end

--- Navigate to the previous conflict
---@param bufnr number Buffer number
---@return boolean found Whether a conflict was found
function M.goto_prev(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local conflicts = M.detect_conflicts(bufnr)

  for i = #conflicts, 1, -1 do
    local conflict = conflicts[i]
    if conflict.start_line < cursor_line then
      vim.api.nvim_win_set_cursor(0, { conflict.start_line, 0 })
      vim.cmd("normal! zz")
      return true
    end
  end

  if #conflicts > 0 then
    vim.api.nvim_win_set_cursor(0, { conflicts[#conflicts].start_line, 0 })
    vim.cmd("normal! zz")
    vim.notify("Wrapped to last conflict", vim.log.levels.INFO)
    return true
  end

  vim.notify("No more conflicts", vim.log.levels.INFO)
  return false
end

--- Show conflict resolution menu modal
---@param bufnr number Buffer number
function M.show_menu(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

  if not conflict then
    vim.notify("No conflict at cursor position", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current_count, incoming_count = resolve.count_sections(conflict)

  local current_preview = ""
  if conflict.current_start and conflict.current_end then
    current_preview = resolve.build_preview(lines, conflict.current_start + 1, conflict.current_end, 3)
  end

  local incoming_preview = ""
  if conflict.incoming_start and conflict.incoming_end then
    incoming_preview = resolve.build_preview(lines, conflict.incoming_start, conflict.incoming_end, 3)
  end

  local options = {
    {
      label = string.format("Accept CURRENT (original) - %d lines", current_count),
      key = "co",
      action = function()
        M.accept_ours(bufnr)
      end,
      preview = current_preview,
    },
    {
      label = string.format("Accept INCOMING (AI suggestion) - %d lines", incoming_count),
      key = "ct",
      action = function()
        M.accept_theirs(bufnr)
      end,
      preview = incoming_preview,
    },
    {
      label = string.format("Accept BOTH versions - %d lines total", current_count + incoming_count),
      key = "cb",
      action = function()
        M.accept_both(bufnr)
      end,
    },
    {
      label = "Delete conflict (accept NONE)",
      key = "cn",
      action = function()
        M.accept_none(bufnr)
      end,
    },
    {
      label = "─────────────────────────",
      key = "",
      action = nil,
      separator = true,
    },
    {
      label = "Next conflict",
      key = "]x",
      action = function()
        M.goto_next(bufnr)
      end,
    },
    {
      label = "Previous conflict",
      key = "[x",
      action = function()
        M.goto_prev(bufnr)
      end,
    },
  }

  local labels = {}
  for _, opt in ipairs(options) do
    if opt.separator then
      table.insert(labels, opt.label)
    else
      table.insert(labels, string.format("[%s] %s", opt.key, opt.label))
    end
  end

  vim.ui.select(labels, {
    prompt = "Resolve Conflict:",
    format_item = function(item)
      return item
    end,
  }, function(choice, idx)
    if not choice or not idx then
      return
    end

    local selected = options[idx]
    if selected and selected.action then
      selected.action()
    end
  end)
end

--- Show floating window menu for conflict resolution
---@param bufnr number Buffer number
function M.show_floating_menu(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local conflict = M.get_conflict_at_cursor(bufnr, cursor[1])

  if not conflict then
    vim.notify("No conflict at cursor position", vim.log.levels.WARN)
    return
  end

  local current_count, incoming_count = resolve.count_sections(conflict)

  local menu_lines = {
    "╭─────────────────────────────────────────╮",
    "│       Resolve Conflict                  │",
    "├─────────────────────────────────────────┤",
    string.format("│ [co] Accept CURRENT (original) %3d lines│", current_count),
    string.format("│ [ct] Accept INCOMING (AI)      %3d lines│", incoming_count),
    string.format("│ [cb] Accept BOTH               %3d lines│", current_count + incoming_count),
    "│ [cn] Delete conflict (NONE)             │",
    "├─────────────────────────────────────────┤",
    "│ []x] Next conflict                      │",
    "│ [[x] Previous conflict                  │",
    "│ [q]  Close menu                         │",
    "╰─────────────────────────────────────────╯",
  }

  local width = 43
  local height = #menu_lines

  local float_opts = {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "none",
    focusable = true,
  }

  local menu_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(menu_bufnr, 0, -1, false, menu_lines)
  vim.bo[menu_bufnr].modifiable = false
  vim.bo[menu_bufnr].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(menu_bufnr, true, float_opts)

  vim.api.nvim_set_hl(0, "CoderConflictMenuBorder", { fg = "#61afef", default = true })
  vim.api.nvim_set_hl(0, "CoderConflictMenuTitle", { fg = "#e5c07b", bold = true, default = true })
  vim.api.nvim_set_hl(0, "CoderConflictMenuKey", { fg = "#98c379", bold = true, default = true })

  vim.wo[win].winhl = "Normal:Normal,FloatBorder:CoderConflictMenuBorder"

  vim.api.nvim_buf_add_highlight(menu_bufnr, -1, "CoderConflictMenuTitle", 1, 0, -1)
  for i = 3, 9 do
    local line = menu_lines[i + 1]
    if line then
      local start_col = line:find("%[")
      local end_col = line:find("%]")
      if start_col and end_col then
        vim.api.nvim_buf_add_highlight(menu_bufnr, -1, "CoderConflictMenuKey", i, start_col - 1, end_col)
      end
    end
  end

  local close_menu = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local menu_opts = { buffer = menu_bufnr, silent = true, noremap = true, nowait = true }

  vim.keymap.set("n", "q", close_menu, menu_opts)
  vim.keymap.set("n", "<Esc>", close_menu, menu_opts)

  vim.keymap.set("n", "co", function()
    close_menu()
    M.accept_ours(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "ct", function()
    close_menu()
    M.accept_theirs(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "cb", function()
    close_menu()
    M.accept_both(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "cn", function()
    close_menu()
    M.accept_none(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "]x", function()
    close_menu()
    M.goto_next(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "[x", function()
    close_menu()
    M.goto_prev(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "1", function()
    close_menu()
    M.accept_ours(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "2", function()
    close_menu()
    M.accept_theirs(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "3", function()
    close_menu()
    M.accept_both(bufnr)
  end, menu_opts)

  vim.keymap.set("n", "4", function()
    close_menu()
    M.accept_none(bufnr)
  end, menu_opts)

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = menu_bufnr,
    once = true,
    callback = close_menu,
  })
end

--- Setup keybindings for conflict resolution in a buffer
---@param bufnr number Buffer number
function M.setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true, noremap = true, nowait = true }

  vim.keymap.set("n", "co", function()
    M.accept_ours(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Accept CURRENT (original) code" }))

  vim.keymap.set("n", "ct", function()
    M.accept_theirs(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Accept INCOMING (AI suggestion) code" }))

  vim.keymap.set("n", "cb", function()
    M.accept_both(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Accept BOTH versions" }))

  vim.keymap.set("n", "cn", function()
    M.accept_none(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Delete conflict (accept NONE)" }))

  vim.keymap.set("n", "]x", function()
    M.goto_next(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Go to next conflict" }))

  vim.keymap.set("n", "[x", function()
    M.goto_prev(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Go to previous conflict" }))

  vim.keymap.set("n", "cm", function()
    M.show_floating_menu(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Show conflict resolution menu" }))

  vim.keymap.set("n", "<CR>", function()
    local cr_cursor = vim.api.nvim_win_get_cursor(0)
    if M.get_conflict_at_cursor(bufnr, cr_cursor[1]) then
      M.show_floating_menu(bufnr)
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end
  end, vim.tbl_extend("force", opts, { desc = "Show conflict menu or default action" }))

  conflict_buffers[bufnr] = {
    keymaps_set = true,
  }
end

--- Remove keybindings from a buffer
---@param bufnr number Buffer number
function M.remove_keymaps(bufnr)
  if not conflict_buffers[bufnr] then
    return
  end

  pcall(vim.keymap.del, "n", "co", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "ct", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "cb", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "cn", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "cm", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "]x", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "[x", { buffer = bufnr })
  pcall(vim.keymap.del, "n", "<CR>", { buffer = bufnr })

  conflict_buffers[bufnr] = nil
end

--- Insert conflict markers for a code change
---@param bufnr number Buffer number
---@param start_line number Start line (1-indexed)
---@param end_line number End line (1-indexed)
---@param new_lines string[] New lines to insert as "incoming"
---@param label? string Optional label for the incoming section
function M.insert_conflict(bufnr, start_line, end_line, new_lines, label)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local line_count = #lines
  start_line = math.max(1, math.min(start_line, line_count + 1))
  end_line = math.max(start_line, math.min(end_line, line_count))

  local current_lines = {}
  for i = start_line, end_line do
    if lines[i] then
      table.insert(current_lines, lines[i])
    end
  end

  local conflict_block = resolve.build_conflict_block(current_lines, new_lines, MARKERS, label)
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, conflict_block)
end

--- Process buffer and auto-show menu for first conflict
---@param bufnr number Buffer number
function M.process_and_show_menu(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local conflict_count = M.process(bufnr)

  if config.auto_show_menu and conflict_count > 0 then
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local win = nil
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == bufnr then
          win = w
          break
        end
      end

      if win then
        vim.api.nvim_set_current_win(win)
        local conflicts = M.detect_conflicts(bufnr)
        if #conflicts > 0 then
          vim.api.nvim_win_set_cursor(win, { conflicts[1].start_line, 0 })
          vim.cmd("normal! zz")
          M.show_floating_menu(bufnr)
        end
      end
    end)
  end
end

--- Process a buffer for conflicts - detect, highlight, and setup keymaps
---@param bufnr number Buffer number
---@return number conflict_count Number of conflicts found
function M.process(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end

  setup_highlights()

  local conflicts = M.detect_conflicts(bufnr)

  if #conflicts > 0 then
    M.highlight_conflicts(bufnr, conflicts)

    if not conflict_buffers[bufnr] then
      M.setup_keymaps(bufnr)
    end

    pcall(function()
      local logs_info = require("codetyper.adapters.nvim.ui.logs.info")
      logs_info(string.format("Found %d conflict(s) - use co/ct/cb/cn to resolve, [x/]x to navigate", #conflicts))
    end)
  else
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, HINT_NAMESPACE, 0, -1)
    M.remove_keymaps(bufnr)
  end

  return #conflicts
end

--- Check if a buffer has conflicts
---@param bufnr number Buffer number
---@return boolean
function M.has_conflicts(bufnr)
  local conflicts = M.detect_conflicts(bufnr)
  return #conflicts > 0
end

--- Get conflict count for a buffer
---@param bufnr number Buffer number
---@return number
function M.count_conflicts(bufnr)
  local conflicts = M.detect_conflicts(bufnr)
  return #conflicts
end

--- Clear all conflicts from a buffer (remove markers but keep chosen code)
---@param bufnr number Buffer number
---@param keep "ours"|"theirs"|"both"|"none" Which version to keep
function M.resolve_all(bufnr, keep)
  local conflicts = M.detect_conflicts(bufnr)

  for i = #conflicts, 1, -1 do
    vim.api.nvim_win_set_cursor(0, { conflicts[i].start_line, 0 })

    if keep == "ours" then
      M.accept_ours(bufnr)
    elseif keep == "theirs" then
      M.accept_theirs(bufnr)
    elseif keep == "both" then
      M.accept_both(bufnr)
    else
      M.accept_none(bufnr)
    end
  end
end

--- Add a buffer to conflict tracking
---@param bufnr number Buffer number
function M.add_tracked_buffer(bufnr)
  if not conflict_buffers[bufnr] then
    conflict_buffers[bufnr] = {}
  end
end

--- Get all tracked buffers with conflicts
---@return number[] buffers List of buffer numbers
function M.get_tracked_buffers()
  local buffers = {}
  for bufnr, _ in pairs(conflict_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and M.has_conflicts(bufnr) then
      table.insert(buffers, bufnr)
    end
  end
  return buffers
end

--- Clear tracking for a buffer
---@param bufnr number Buffer number
function M.clear_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, HINT_NAMESPACE, 0, -1)
  M.remove_keymaps(bufnr)
  conflict_buffers[bufnr] = nil
end

--- Initialize the conflict module
function M.setup()
  setup_highlights()

  vim.api.nvim_create_autocmd("BufDelete", {
    group = vim.api.nvim_create_augroup("CoderConflict", { clear = true }),
    callback = function(ev)
      conflict_buffers[ev.buf] = nil
    end,
  })
end

return M
