local state = require("codetyper.state.state")
local prompts = require("codetyper.prompts.agents.diff")
local generate_diff_lines = require("codetyper.adapters.nvim.ui.diff_review.generate_diff_lines")

--- Update the diff view for current entry
local function update_diff_view()
  if not state.diff_buf or not vim.api.nvim_buf_is_valid(state.diff_buf) then
    return
  end

  local entry = state.entries[state.current_index]
  local ui_prompts = prompts.review
  if not entry then
    vim.bo[state.diff_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, { ui_prompts.messages.no_changes_short })
    vim.bo[state.diff_buf].modifiable = false
    return
  end

  local lines = {}

  local status_icon = entry.applied and " " or (entry.approved and " " or " ")
  local op_icon = entry.operation == "create" and "+" or (entry.operation == "delete" and "-" or "~")
  local current_status = entry.applied and ui_prompts.status.applied
    or (entry.approved and ui_prompts.status.approved or ui_prompts.status.pending)

  table.insert(
    lines,
    string.format(ui_prompts.diff_header.top, status_icon, op_icon, vim.fn.fnamemodify(entry.path, ":t"))
  )
  table.insert(lines, string.format(ui_prompts.diff_header.path, entry.path))
  table.insert(lines, string.format(ui_prompts.diff_header.op, entry.operation))
  table.insert(lines, string.format(ui_prompts.diff_header.status, current_status))
  table.insert(lines, ui_prompts.diff_header.bottom)
  table.insert(lines, "")

  local diff_lines = generate_diff_lines(entry.original, entry.modified, entry.path)
  for _, line in ipairs(diff_lines) do
    table.insert(lines, line)
  end

  vim.bo[state.diff_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.diff_buf, 0, -1, false, lines)
  vim.bo[state.diff_buf].modifiable = false
  vim.bo[state.diff_buf].filetype = "diff"
end

return update_diff_view
