local log = require("codetyper.adapters.nvim.ui.logs.log")
local params = require("codetyper.params.agents.logs")

--- Log tool execution
---@param tool_name string Name of the tool
---@param status string "start" | "success" | "error" | "approval"
---@param details? string Additional details
local function tool(tool_name, status, details)
  local icons = params.icons

  local message = string.format("[%s] %s", icons[status] or status, tool_name)
  if details then
    message = message .. ": " .. details
  end

  log("tool", message, {
    tool = tool_name,
    status = status,
    details = details,
  })
end

return tool
