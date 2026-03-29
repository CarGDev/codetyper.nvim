--- Terminal window — toggleable bottom terminal panel
local M = {}

local state = {
  buf = nil,
  win = nil,
  job_id = nil,
}

--- Close the terminal window
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

--- Open a terminal in a bottom split
function M.open()
  -- If already open, focus it
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  -- Reuse buffer if still valid
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local height = math.max(10, math.floor(vim.o.lines * 0.3))
    vim.cmd("botright split")
    state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win, state.buf)
    vim.api.nvim_win_set_height(state.win, height)
    vim.cmd("startinsert")
    return
  end

  -- Create new terminal
  local height = math.max(10, math.floor(vim.o.lines * 0.3))
  vim.cmd("botright split")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(state.win, height)

  vim.cmd("terminal")
  state.buf = vim.api.nvim_get_current_buf()
  state.job_id = vim.b.terminal_job_id

  vim.bo[state.buf].buflisted = false

  -- Keymaps for the terminal buffer
  local opts = { buffer = state.buf, silent = true }
  vim.keymap.set("t", "<Esc><Esc>", function()
    vim.cmd("stopinsert")
  end, opts)
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)

  vim.cmd("startinsert")
end

--- Toggle the terminal window
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

--- Send a command to the terminal
---@param cmd string Command to send
function M.send(cmd)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    M.open()
    -- Wait a tick for terminal to initialize
    vim.defer_fn(function()
      if state.job_id then
        vim.fn.chansend(state.job_id, cmd .. "\n")
      end
    end, 100)
    return
  end

  if state.job_id then
    -- Ensure terminal is visible
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
      M.open()
    end
    vim.fn.chansend(state.job_id, cmd .. "\n")
  end
end

--- Check if terminal is open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
