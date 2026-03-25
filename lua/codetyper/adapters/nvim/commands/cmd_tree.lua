local utils = require("codetyper.support.utils")

--- Refresh tree.log manually
local function cmd_tree()
  local tree = require("codetyper.support.tree")
  if tree.update_tree_log() then
    utils.notify("Tree log updated: " .. tree.get_tree_log_path())
  else
    utils.notify("Failed to update tree log", vim.log.levels.ERROR)
  end
end

return cmd_tree
