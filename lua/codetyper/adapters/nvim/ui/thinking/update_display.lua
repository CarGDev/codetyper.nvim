local state = require("codetyper.state.state")
local active_count = require("codetyper.adapters.nvim.ui.thinking.active_count")

--- Update the thinking window buffer text with spinner icon and request count
---@param icon string Spinner icon character
---@param force? boolean Show even when active count is 0
local function update_display(icon, force)
  if not state.buf_id or not vim.api.nvim_buf_is_valid(state.buf_id) then
    return
  end
  local count = active_count()
  if count <= 0 and not force then
    return
  end
  local text = state.stage_text or "Thinking..."
  local line = (count <= 1) and (icon .. " " .. text)
    or (icon .. " " .. text .. " (" .. tostring(count) .. " requests)")
  vim.schedule(function()
    if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
      vim.bo[state.buf_id].modifiable = true
      vim.api.nvim_buf_set_lines(state.buf_id, 0, -1, false, { line })
      vim.bo[state.buf_id].modifiable = false
    end
  end)
end

return update_display
