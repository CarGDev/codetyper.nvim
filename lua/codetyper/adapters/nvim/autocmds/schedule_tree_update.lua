local tree_update_timer = require("codetyper.constants.constants").tree_update_timer
local TREE_UPDATE_DEBOUNCE_MS = require("codetyper.constants.constants").TREE_UPDATE_DEBOUNCE_MS

--- Schedule tree update with debounce
local function schedule_tree_update()
  if tree_update_timer then
    tree_update_timer:stop()
  end

  tree_update_timer = vim.defer_fn(function()
    local tree = require("codetyper.support.tree")
    tree.update_tree_log()
    tree_update_timer = nil
  end, TREE_UPDATE_DEBOUNCE_MS)
end

return schedule_tree_update
