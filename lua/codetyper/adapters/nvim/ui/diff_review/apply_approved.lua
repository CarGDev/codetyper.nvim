local state = require("codetyper.state.state")
local utils = require("codetyper.support.utils")
local prompts = require("codetyper.prompts.agents.diff")
local update_file_list = require("codetyper.adapters.nvim.ui.diff_review.update_file_list")
local update_diff_view = require("codetyper.adapters.nvim.ui.diff_review.update_diff_view")

--- Apply all approved changes to disk
---@return number applied_count Number of successfully applied changes
local function apply_approved()
  local applied_count = 0

  for _, entry in ipairs(state.entries) do
    if entry.approved and not entry.applied then
      if entry.operation == "create" or entry.operation == "edit" then
        local write_success = utils.write_file(entry.path, entry.modified)
        if write_success then
          entry.applied = true
          applied_count = applied_count + 1
        end
      elseif entry.operation == "delete" then
        local delete_success = os.remove(entry.path)
        if delete_success then
          entry.applied = true
          applied_count = applied_count + 1
        end
      end
    end
  end

  update_file_list()
  update_diff_view()

  if applied_count > 0 then
    utils.notify(string.format(prompts.review.messages.applied_count, applied_count))
  end

  return applied_count
end

return apply_approved
