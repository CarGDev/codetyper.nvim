local state = require("codetyper.state.state")
local update_file_list = require("codetyper.adapters.nvim.ui.diff_review.update_file_list")
local update_diff_view = require("codetyper.adapters.nvim.ui.diff_review.update_diff_view")

--- Reject the currently selected diff entry
local function reject_current()
  local entry = state.entries[state.current_index]
  if entry and not entry.applied then
    entry.approved = false
    update_file_list()
    update_diff_view()
  end
end

return reject_current
