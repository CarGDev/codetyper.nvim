---@mod codetyper.chat_switcher Modal picker to switch between Ask and Agent modes

local M = {}

--- Show modal to switch between chat modes
function M.show()
  local items = {
    { label = "Ask", desc = "Q&A mode - ask questions about code", mode = "ask" },
    { label = "Agent", desc = "Agent mode - can read/edit files", mode = "agent" },
  }

  vim.ui.select(items, {
    prompt = "Select Chat Mode:",
    format_item = function(item)
      return item.label .. " - " .. item.desc
    end,
  }, function(choice)
    if not choice then
      return
    end

    -- Close current panel first
    local ask = require("codetyper.features.ask.engine")
    local agent_ui = require("codetyper.adapters.nvim.ui.chat")

    if ask.is_open() then
      ask.close()
    end
    if agent_ui.is_open() then
      agent_ui.close()
    end

    -- Open selected mode
    vim.schedule(function()
      if choice.mode == "ask" then
        ask.open()
      elseif choice.mode == "agent" then
        agent_ui.open()
      end
    end)
  end)
end

return M
