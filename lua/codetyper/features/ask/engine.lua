---@mod codetyper.ask Ask window for Codetyper.nvim
---
--- Thin wrapper that delegates to the unified chat UI with ASK mode.
--- Maintained for backwards compatibility.

local M = {}

-- Forward to unified chat UI
local function get_chat()
  return require("codetyper.adapters.nvim.ui.chat")
end

--- Open the ask panel (delegates to unified chat in ASK mode)
---@param selection table|nil Visual selection context {text, start_line, end_line, filepath, filename, language}
function M.open(selection)
  get_chat().open({ mode = "ask", selection = selection })
end

--- Close the ask panel
function M.close()
  get_chat().close()
end

--- Toggle the ask panel
function M.toggle()
  local chat = get_chat()
  if chat.is_open() then
    if chat.get_mode() == "ask" then
      chat.close()
    else
      chat.set_mode("ask")
    end
  else
    chat.open({ mode = "ask" })
  end
end

--- Focus the input window
function M.focus_input()
  get_chat().focus_input()
end

--- Focus the output/chat window
function M.focus_output()
  get_chat().focus_chat()
end

--- Clear chat history
function M.clear_history()
  local chat = get_chat()
  if chat.is_open() then
    -- Trigger /clear command equivalent
    chat.set_mode("ask") -- Ensure we're in ask mode
    -- Clear is handled by the chat itself
  end
end

--- Start a new chat (clears history and input)
function M.new_chat()
  M.clear_history()
  M.focus_input()
end

--- Check if ask panel is open
---@return boolean
function M.is_open()
  local chat = get_chat()
  return chat.is_open() and chat.get_mode() == "ask"
end

--- Get chat history (for backwards compatibility)
---@return table History
function M.get_history()
  -- History is now managed by unified chat
  return {}
end

--- Show chat mode switcher modal
function M.show_chat_switcher()
  local switcher = require("codetyper.adapters.nvim.ui.switcher")
  switcher.show()
end

--- Add visual selection as context
---@param selection table Selection info
function M.add_selection_context(selection)
  get_chat().add_selection_context(selection)
end

return M
