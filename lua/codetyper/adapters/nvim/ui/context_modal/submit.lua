local state = require("codetyper.state.state")
local close = require("codetyper.adapters.nvim.ui.context_modal.close")

--- Submit the additional context from the modal buffer
local function submit()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local additional_context = table.concat(lines, "\n")

  additional_context = additional_context:match("^%s*(.-)%s*$") or additional_context

  if additional_context == "" then
    close()
    return
  end

  local original_event = state.original_event
  local callback = state.callback
  local attached_files = state.attached_files

  close()

  if callback and original_event then
    callback(original_event, additional_context, attached_files)
  end
end

return submit
