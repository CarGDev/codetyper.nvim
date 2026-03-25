local state = require("codetyper.state.state")
local run_suggested_command = require("codetyper.adapters.nvim.ui.context_modal.run_suggested_command")

--- Run all suggested shell commands and append their outputs to the modal buffer
---@param commands table[] List of {label, cmd} suggested command entries
local function run_all_suggested_commands(commands)
  for _, command in ipairs(commands) do
    pcall(run_suggested_command, command)
  end

  vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  vim.cmd("startinsert")
end

return run_all_suggested_commands
