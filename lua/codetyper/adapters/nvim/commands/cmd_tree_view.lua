local utils = require("codetyper.support.utils")

--- Open tree.log file in a vertical split
local function cmd_tree_view()
  local tree = require("codetyper.support.tree")
  local tree_log_path = tree.get_tree_log_path()

  if not tree_log_path then
    utils.notify("Could not find tree.log", vim.log.levels.WARN)
    return
  end

  tree.update_tree_log()

  vim.cmd("vsplit " .. vim.fn.fnameescape(tree_log_path))
  vim.bo.readonly = true
  vim.bo.modifiable = false
end

return cmd_tree_view
