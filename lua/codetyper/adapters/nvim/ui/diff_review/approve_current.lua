local state = require("codetyper.state.state")
local update_file_list = require("codetyper.adapters.nvim.ui.diff_review.update_file_list")
local update_diff_view = require("codetyper.adapters.nvim.ui.diff_review.update_diff_view")

--- Approve the currently selected diff entry
local function approve_current()
  local entry = state.entries[state.current_index]
  if entry and not entry.applied then
    entry.approved = true
    update_file_list()
    update_diff_view()
  end
end

return approve_current
