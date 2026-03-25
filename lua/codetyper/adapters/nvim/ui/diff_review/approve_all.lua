local state = require("codetyper.state.state")
local update_file_list = require("codetyper.adapters.nvim.ui.diff_review.update_file_list")
local update_diff_view = require("codetyper.adapters.nvim.ui.diff_review.update_diff_view")

--- Approve all unapplied diff entries
local function approve_all()
  for _, entry in ipairs(state.entries) do
    if not entry.applied then
      entry.approved = true
    end
  end
  update_file_list()
  update_diff_view()
end

return approve_all
