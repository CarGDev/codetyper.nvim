local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log update/edit operation
---@param filepath string Path of file being edited
---@param added? number Lines added
---@param removed? number Lines removed
local function update(filepath, added, removed)
  local message = string.format("Update(%s)", vim.fn.fnamemodify(filepath, ":~:."))
  if added or removed then
    local parts = {}
    if added and added > 0 then
      table.insert(parts, string.format("Added %d lines", added))
    end
    if removed and removed > 0 then
      table.insert(parts, string.format("Removed %d lines", removed))
    end
    if #parts > 0 then
      message = message .. "\n  ⎿  " .. table.concat(parts, ", ")
    end
  end
  log("action", message)
end

return update
