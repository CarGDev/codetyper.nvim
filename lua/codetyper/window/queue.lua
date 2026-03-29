--- Queue window — right-side panel showing pending/processing prompt events
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local state = {
  buf = nil,
  win = nil,
  refresh_timer = nil,
}

--- Close the queue window
function M.close()
  if state.refresh_timer then
    state.refresh_timer:stop()
    state.refresh_timer = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

--- Build queue content lines
---@return string[]
local function build_content()
  local queue = require("codetyper.core.events.queue")
  local lines = {}

  table.insert(lines, " Queue")
  table.insert(lines, " ─────────────────────────────")
  table.insert(lines, "")

  local all_stats = queue.stats()
  table.insert(lines, string.format(" Total: %d  Pending: %d  Processing: %d",
    all_stats.total, all_stats.pending, all_stats.processing))
  table.insert(lines, "")

  -- Show pending events
  local pending = queue.get_pending()
  if #pending > 0 then
    table.insert(lines, " Pending:")
    for _, event in ipairs(pending) do
      local intent = event.intent and event.intent.type or "?"
      local target = event.target_path and vim.fn.fnamemodify(event.target_path, ":t") or "?"
      local prompt_preview = (event.prompt_content or ""):sub(1, 40):gsub("\n", " ")
      table.insert(lines, string.format("  [%s] %s:%s", intent, target, prompt_preview))
      if event.range then
        table.insert(lines, string.format("        lines %d-%d", event.range.start_line, event.range.end_line))
      end
    end
    table.insert(lines, "")
  end

  -- Show processing events
  local processing = queue.get_processing()
  if #processing > 0 then
    table.insert(lines, " Processing:")
    for _, event in ipairs(processing) do
      local intent = event.intent and event.intent.type or "?"
      local prompt_preview = (event.prompt_content or ""):sub(1, 40):gsub("\n", " ")
      table.insert(lines, string.format("  [%s] %s", intent, prompt_preview))
    end
    table.insert(lines, "")
  end

  if #pending == 0 and #processing == 0 then
    table.insert(lines, " No items in queue.")
    table.insert(lines, "")
  end

  -- Show autotrigger status
  local constants = require("codetyper.constants.constants")
  table.insert(lines, " ─────────────────────────────")
  table.insert(lines, string.format(" Autotrigger: %s", constants.autotrigger and "ON" or "OFF"))
  table.insert(lines, "")
  table.insert(lines, " 'q' close | 'r' refresh | 'a' toggle auto")
  table.insert(lines, " 'p' process tags | 'c' clear queue")

  return lines
end

--- Refresh the queue window content
function M.refresh()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = build_content()
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

--- Open the queue window
function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.refresh()
    return
  end

  flog.info("queue_window", "opening") -- TODO: remove after debugging

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "codetyper-queue"

  local width = math.max(35, math.floor(vim.o.columns * 0.25))
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, width)

  vim.wo[state.win].wrap = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].cursorline = false

  M.refresh()

  -- Keymaps
  local opts = { buffer = state.buf, silent = true }
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "r", function()
    M.refresh()
  end, opts)
  vim.keymap.set("n", "a", function()
    local constants = require("codetyper.constants.constants")
    constants.autotrigger = not constants.autotrigger
    vim.notify("Autotrigger: " .. (constants.autotrigger and "ON" or "OFF"), vim.log.levels.INFO)
    M.refresh()
  end, opts)
  vim.keymap.set("n", "p", function()
    local check_all = require("codetyper.adapters.nvim.autocmds.check_all_prompts")
    check_all()
    vim.defer_fn(function()
      M.refresh()
    end, 500)
  end, opts)
  vim.keymap.set("n", "c", function()
    local queue = require("codetyper.core.events.queue")
    queue.clear()
    vim.notify("Queue cleared", vim.log.levels.INFO)
    M.refresh()
  end, opts)

  -- Auto-refresh every 2 seconds while open
  state.refresh_timer = vim.loop.new_timer()
  state.refresh_timer:start(2000, 2000, vim.schedule_wrap(function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      M.refresh()
    else
      if state.refresh_timer then
        state.refresh_timer:stop()
        state.refresh_timer = nil
      end
    end
  end))

  -- Return focus to previous window
  vim.cmd("wincmd p")
end

--- Toggle the queue window
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

--- Check if open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
