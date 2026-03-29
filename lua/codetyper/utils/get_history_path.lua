local COST_HISTORY_FILE = require("codetyper.constants.defaults").COST_HISTORY_FILE
local utils = require("codetyper.support.utils")

--- Get path to cost history file
---@return string File path
local function get_history_path()
  local root = utils.get_project_root()
  return root .. COST_HISTORY_FILE
end

return get_history_path
