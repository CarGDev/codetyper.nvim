local ignored_directories = require("codetyper.adapters.nvim.autocmds.ignored_directories")

--- Check if a file path contains an ignored directory
---@param filepath string Full file path
---@return boolean
local function is_in_ignored_directory(filepath)
  for _, dir in ipairs(ignored_directories) do
    if filepath:match("/" .. dir .. "/") or filepath:match("/" .. dir .. "$") then
      return true
    end
    if filepath:match("^" .. dir .. "/") then
      return true
    end
  end
  return false
end

return is_in_ignored_directory
