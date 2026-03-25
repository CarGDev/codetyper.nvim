local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log task completion
---@param next_task? string Next task
local function task_done(next_task)
  local message = "  ⎿  Done"
  if next_task then
    message = message .. "\n✶ " .. next_task
  end
  log("result", message)
end

return task_done
