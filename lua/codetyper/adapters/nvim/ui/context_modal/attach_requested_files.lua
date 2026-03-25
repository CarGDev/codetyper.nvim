local state = require("codetyper.state.state")
local parse_requested_files = require("codetyper.utils.parse_requested_files")

--- Attach parsed files from LLM response into the modal buffer
local function attach_requested_files()
  if not state.llm_response or state.llm_response == "" then
    return
  end

  local resolved_files = parse_requested_files(state.llm_response)

  if #resolved_files == 0 then
    local ui_prompts = require("codetyper.prompts.agents.modal").ui
    vim.api.nvim_buf_set_lines(state.buf, vim.api.nvim_buf_line_count(state.buf), -1, false, ui_prompts.files_header)
    return
  end

  state.attached_files = state.attached_files or {}

  for _, file_path in ipairs(resolved_files) do
    local read_success, file_lines = pcall(vim.fn.readfile, file_path)
    if read_success and file_lines and #file_lines > 0 then
      table.insert(state.attached_files, {
        path = vim.fn.fnamemodify(file_path, ":~:."),
        full_path = file_path,
        content = table.concat(file_lines, "\n"),
      })
      local insert_at = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_buf_set_lines(state.buf, insert_at, insert_at, false, { "", "-- Attached: " .. file_path .. " --" })
      for line_index, line_content in ipairs(file_lines) do
        vim.api.nvim_buf_set_lines(
          state.buf,
          insert_at + 1 + line_index,
          insert_at + 1 + line_index,
          false,
          { line_content }
        )
      end
    else
      local insert_at = vim.api.nvim_buf_line_count(state.buf)
      vim.api.nvim_buf_set_lines(
        state.buf,
        insert_at,
        insert_at,
        false,
        { "", "-- Failed to read: " .. file_path .. " --" }
      )
    end
  end

  vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  vim.cmd("startinsert")
end

return attach_requested_files
