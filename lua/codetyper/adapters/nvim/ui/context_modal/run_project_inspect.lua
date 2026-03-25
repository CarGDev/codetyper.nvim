local state = require("codetyper.state.state")

--- Run a small set of safe project inspection commands and insert outputs into the modal buffer
local function run_project_inspect()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local inspection_commands = {
    { label = "List files (ls -la)", cmd = "ls -la" },
    { label = "Git status (git status --porcelain)", cmd = "git status --porcelain" },
    { label = "Git top (git rev-parse --show-toplevel)", cmd = "git rev-parse --show-toplevel" },
    { label = "Show repo files (git ls-files)", cmd = "git ls-files" },
  }

  local ui_prompts = require("codetyper.prompts.agents.modal").ui
  local insert_pos = vim.api.nvim_buf_line_count(state.buf)
  vim.api.nvim_buf_set_lines(state.buf, insert_pos, insert_pos, false, ui_prompts.project_inspect_header)

  for _, command in ipairs(inspection_commands) do
    local run_success, output_lines = pcall(vim.fn.systemlist, command.cmd)
    if run_success and output_lines and #output_lines > 0 then
      vim.api.nvim_buf_set_lines(
        state.buf,
        insert_pos + 2,
        insert_pos + 2,
        false,
        { "-- " .. command.label .. " --" }
      )
      for line_index, line_content in ipairs(output_lines) do
        vim.api.nvim_buf_set_lines(
          state.buf,
          insert_pos + 2 + line_index,
          insert_pos + 2 + line_index,
          false,
          { line_content }
        )
      end
      insert_pos = vim.api.nvim_buf_line_count(state.buf)
    else
      vim.api.nvim_buf_set_lines(
        state.buf,
        insert_pos + 2,
        insert_pos + 2,
        false,
        { "-- " .. command.label .. " --", "(no output or command failed)" }
      )
      insert_pos = vim.api.nvim_buf_line_count(state.buf)
    end
  end

  vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  vim.cmd("startinsert")
end

return run_project_inspect
