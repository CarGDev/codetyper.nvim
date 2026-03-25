local state = require("codetyper.state.state")

--- Run a single suggested shell command and append its output to the modal buffer
---@param command table A {label, cmd} suggested command entry
local function run_suggested_command(command)
  if not command or not command.cmd then
    return
  end

  local run_success, output_lines = pcall(vim.fn.systemlist, command.cmd)
  local insert_at = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, { "", "-- Output: " .. command.cmd .. " --" })

  if run_success and output_lines and #output_lines > 0 then
    for line_index, line_content in ipairs(output_lines) do
      vim.api.nvim_buf_set_lines(
        state.buf,
        insert_at + line_index,
        insert_at + line_index,
        false,
        { line_content }
      )
    end
  else
    vim.api.nvim_buf_set_lines(
      state.buf,
      insert_at + 1,
      insert_at + 1,
      false,
      { "(no output or command failed)" }
    )
  end

  vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  vim.cmd("startinsert")
end

return run_suggested_command
