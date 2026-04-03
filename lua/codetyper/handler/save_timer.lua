--- Save all usage to disk (debounced)
local get_history_path = require("codetyper.utils.get_history_path")
local utils = require("codetyper.support.utils")
local state = require("codetyper.state.state")
local constants = require("codetyper.constants.constants")

local function save_to_disk()
  -- Cancel existing timer
  if constants.save_timer then
    constants.save_timer:stop()
    constants.save_timer = nil
  end

  -- Debounce writes (500ms)
  constants.save_timer = vim.loop.new_timer()
  constants.save_timer:start(
    500,
    0,
    vim.schedule_wrap(function()
      local history_path = get_history_path()

      -- Ensure directory exists
      local dir = vim.fn.fnamemodify(history_path, ":h")
      utils.ensure_dir(dir)

      -- Merge session and historical usage
      local all_data = vim.deepcopy(state.all_usage)
      for _, usage in ipairs(state.usage) do
        table.insert(all_data, usage)
      end

      -- Save to file
      local data = {
        version = 1,
        updated = os.time(),
        usage = all_data,
      }

      local ok, json = pcall(vim.json.encode, data)
      if ok then
        utils.write_file(history_path, json)
      end

      constants.save_timer = nil
    end)
  )
end

return save_to_disk
