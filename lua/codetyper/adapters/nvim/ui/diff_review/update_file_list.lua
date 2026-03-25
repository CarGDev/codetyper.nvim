local state = require("codetyper.state.state")
local prompts = require("codetyper.prompts.agents.diff")

--- Update the file list sidebar
local function update_file_list()
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
    return
  end

  local ui_prompts = prompts.review
  local lines = {}
  table.insert(lines, string.format(ui_prompts.list_menu.top, #state.entries))
  for _, item in ipairs(ui_prompts.list_menu.items) do
    table.insert(lines, item)
  end
  table.insert(lines, ui_prompts.list_menu.bottom)
  table.insert(lines, "")

  for entry_index, entry in ipairs(state.entries) do
    local prefix = (entry_index == state.current_index) and "▶ " or "  "
    local status = entry.applied and "" or (entry.approved and "" or "○")
    local operation_icon = entry.operation == "create" and "[+]" or (entry.operation == "delete" and "[-]" or "[~]")
    local filename = vim.fn.fnamemodify(entry.path, ":t")

    table.insert(lines, string.format("%s%s %s %s", prefix, status, operation_icon, filename))
  end

  if #state.entries == 0 then
    table.insert(lines, ui_prompts.messages.no_changes)
  end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false

  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    local target_line = 9 + state.current_index - 1
    if target_line <= vim.api.nvim_buf_line_count(state.list_buf) then
      vim.api.nvim_win_set_cursor(state.list_win, { target_line, 0 })
    end
  end
end

return update_file_list
