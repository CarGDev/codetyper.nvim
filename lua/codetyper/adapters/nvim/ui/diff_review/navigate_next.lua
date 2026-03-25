local state = require("codetyper.state.state")
local update_file_list = require("codetyper.adapters.nvim.ui.diff_review.update_file_list")
local update_diff_view = require("codetyper.adapters.nvim.ui.diff_review.update_diff_view")

--- Navigate to next diff entry
local function navigate_next()
  if state.current_index < #state.entries then
    state.current_index = state.current_index + 1
    update_file_list()
    update_diff_view()
  end
end

return navigate_next
