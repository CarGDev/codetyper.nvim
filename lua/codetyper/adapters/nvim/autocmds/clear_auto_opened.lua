local autocmds_state = require("codetyper.adapters.nvim.autocmds.state")

--- Clear auto-opened tracking for a buffer
---@param bufnr number Buffer number
local function clear_auto_opened(bufnr)
  autocmds_state.auto_opened_buffers[bufnr] = nil
end

return clear_auto_opened
