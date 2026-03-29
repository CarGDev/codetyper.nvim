local M = {}

local state = require("codetyper.state.state")
local utils = require("codetyper.support.utils")
local get_history_path = require("codetyper.utils.get_history_path")

--- Clear session usage (not history)
function M.clear_session()
  state.usage = {}
  state.session_start = os.time()
  utils.notify("Session cost tracking cleared", vim.log.levels.INFO)
end

--- Clear all history (session + saved)
function M.clear_all()
  state.usage = {}
  state.all_usage = {}
  state.session_start = os.time()
  state.loaded = false

  local history_path = get_history_path()
  local ok, err = os.remove(history_path)
  if not ok and err and not err:match("No such file") then
    utils.notify("Failed to delete history: " .. err, vim.log.levels.WARN)
  end

  utils.notify("All cost history cleared", vim.log.levels.INFO)
end

--- Clear usage history (alias for clear_session)
function M.clear()
  M.clear_session()
end

--- Reset session
function M.reset()
  M.clear_session()
end

return M
