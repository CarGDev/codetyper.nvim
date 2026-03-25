local state = require("codetyper.state.state")
local utils = require("codetyper.support.utils")
local prompts = require("codetyper.prompts.agents.diff")
local update_file_list = require("codetyper.adapters.nvim.ui.diff_review.update_file_list")
local update_diff_view = require("codetyper.adapters.nvim.ui.diff_review.update_diff_view")
local navigate_next = require("codetyper.adapters.nvim.ui.diff_review.navigate_next")
local navigate_prev = require("codetyper.adapters.nvim.ui.diff_review.navigate_prev")
local approve_current = require("codetyper.adapters.nvim.ui.diff_review.approve_current")
local reject_current = require("codetyper.adapters.nvim.ui.diff_review.reject_current")
local approve_all = require("codetyper.adapters.nvim.ui.diff_review.approve_all")
local close = require("codetyper.adapters.nvim.ui.diff_review.close")

--- Open the diff review UI
local function open()
  if state.is_open then
    return
  end

  if #state.entries == 0 then
    utils.notify(prompts.review.messages.no_changes_short, vim.log.levels.INFO)
    return
  end

  state.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.list_buf].buftype = "nofile"
  vim.bo[state.list_buf].bufhidden = "wipe"
  vim.bo[state.list_buf].swapfile = false

  state.diff_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.diff_buf].buftype = "nofile"
  vim.bo[state.diff_buf].bufhidden = "wipe"
  vim.bo[state.diff_buf].swapfile = false

  vim.cmd("tabnew")
  state.diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)

  vim.cmd("topleft vsplit")
  state.list_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.list_win, state.list_buf)
  vim.api.nvim_win_set_width(state.list_win, 35)

  for _, win in ipairs({ state.list_win, state.diff_win }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
  end

  local list_keymap_opts = { buffer = state.list_buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", navigate_next, list_keymap_opts)
  vim.keymap.set("n", "k", navigate_prev, list_keymap_opts)
  vim.keymap.set("n", "<Down>", navigate_next, list_keymap_opts)
  vim.keymap.set("n", "<Up>", navigate_prev, list_keymap_opts)
  vim.keymap.set("n", "<CR>", function()
    vim.api.nvim_set_current_win(state.diff_win)
  end, list_keymap_opts)
  vim.keymap.set("n", "a", approve_current, list_keymap_opts)
  vim.keymap.set("n", "r", reject_current, list_keymap_opts)
  vim.keymap.set("n", "A", approve_all, list_keymap_opts)
  vim.keymap.set("n", "q", close, list_keymap_opts)
  vim.keymap.set("n", "<Esc>", close, list_keymap_opts)

  local diff_keymap_opts = { buffer = state.diff_buf, noremap = true, silent = true }
  vim.keymap.set("n", "j", navigate_next, diff_keymap_opts)
  vim.keymap.set("n", "k", navigate_prev, diff_keymap_opts)
  vim.keymap.set("n", "<Tab>", function()
    vim.api.nvim_set_current_win(state.list_win)
  end, diff_keymap_opts)
  vim.keymap.set("n", "a", approve_current, diff_keymap_opts)
  vim.keymap.set("n", "r", reject_current, diff_keymap_opts)
  vim.keymap.set("n", "A", approve_all, diff_keymap_opts)
  vim.keymap.set("n", "q", close, diff_keymap_opts)
  vim.keymap.set("n", "<Esc>", close, diff_keymap_opts)

  state.is_open = true
  state.current_index = 1

  update_file_list()
  update_diff_view()

  vim.api.nvim_set_current_win(state.list_win)
end

return open
