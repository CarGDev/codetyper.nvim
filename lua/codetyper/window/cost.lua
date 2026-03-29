local M = {}

local state = require("codetyper.state.state")
local stats_mod = require("codetyper.core.cost.stats")
local view = require("codetyper.core.cost.view")
local fmt = require("codetyper.core.cost.format")
local session = require("codetyper.core.cost.session")
local normalize_model = require("codetyper.handler.normalize_model")
local is_free_model = require("codetyper.core.cost.is_free_model")
local pricing = require("codetyper.constants.prices")
local comparison_model = require("codetyper.constants.models").comparison_model
local load_from_history = require("codetyper.utils.load_from_history")

local view_deps = {
  comparison_model = comparison_model,
  pricing = pricing,
  normalize_model = normalize_model,
  is_free = is_free_model,
  formatters = fmt,
}

--- Refresh the cost window content
function M.refresh_window()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local session_stats = stats_mod.get_stats()
  local all_time_stats = stats_mod.get_all_time_stats()
  local lines = view.generate_content(session_stats, all_time_stats, view_deps)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

--- Open the cost estimation window
function M.open()
  load_from_history()

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "codetyper-cost"

  local width = 58
  local height = 40
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Cost Estimation ",
    title_pos = "center",
  })

  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = false

  M.refresh_window()

  local opts = { buffer = state.buf, silent = true }
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "r", function()
    M.refresh_window()
  end, opts)
  vim.keymap.set("n", "c", function()
    session.clear_session()
    M.refresh_window()
  end, opts)
  vim.keymap.set("n", "C", function()
    session.clear_all()
    M.refresh_window()
  end, opts)

  vim.api.nvim_buf_call(state.buf, function()
    vim.fn.matchadd("Title", "LLM Cost Estimation")
    vim.fn.matchadd("Number", "\\$[0-9.]*")
    vim.fn.matchadd("Keyword", "[0-9.]*[KM]\\? tokens")
    vim.fn.matchadd("Special", "🤖\\|💰\\|📊\\|📈\\|💵")
  end)
end

--- Close the cost window
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

--- Toggle the cost window
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

return M
