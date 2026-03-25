local log = require("codetyper.adapters.nvim.ui.logs.log")

--- Log file read operation
---@param filepath string Path of file being read
---@param lines? number Number of lines read
local function read(filepath, lines)
  local message = string.format("Read(%s)", vim.fn.fnamemodify(filepath, ":~:."))
  if lines then
    message = message .. string.format("\n  ⎿  Read %d lines", lines)
  end
  log("action", message)
end

return read
