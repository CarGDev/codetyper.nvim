local M = {}
local utils = require("codetyper.support.utils")

--- Preview code in a floating window before injection
---@param code string Generated code
---@param callback fun(action: string) Callback with selected action
function M.preview(code, callback)
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  local lines = vim.split(code, "\n", { plain = true })

  -- Create buffer for preview
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate window size
  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = config.window.border,
    title = " Generated Code Preview ",
    title_pos = "center",
  })

  -- Set buffer options
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Add keymaps for actions
  local opts = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
    callback("cancel")
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    vim.api.nvim_win_close(win, true)
    callback("inject")
  end, opts)

  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", code)
    utils.notify("Copied to clipboard")
  end, opts)

  -- Show help in command line
  vim.api.nvim_echo({
    { "Press ", "Normal" },
    { "<CR>", "Keyword" },
    { " to inject, ", "Normal" },
    { "y", "Keyword" },
    { " to copy, ", "Normal" },
    { "q", "Keyword" },
    { " to cancel", "Normal" },
  }, false, {})
end

return M
