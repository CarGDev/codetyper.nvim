local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log a task/step that's in progress
---@param task_name string Task name
---@param status string|nil Status message
local function task(task_name, status)
  local message = task_name
  if status then
    message = message .. " " .. status
  end
  log("task", message)
end

return task
