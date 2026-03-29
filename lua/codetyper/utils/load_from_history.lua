local state = require("codetyper.state.state")
local utils = require("codetyper.support.utils")
local get_history_path = require("codetyper.utils.get_history_path")

--- Load historical usage from disk
local function load_from_history()
  if state.loaded then
    return
  end

  local history_path = get_history_path()
  local content = utils.read_file(history_path)

  if content and content ~= "" then
    local ok, data = pcall(vim.json.decode, content)
    if ok and data and data.usage then
      state.all_usage = data.usage
    end
  end

  state.loaded = true
end

return load_from_history
