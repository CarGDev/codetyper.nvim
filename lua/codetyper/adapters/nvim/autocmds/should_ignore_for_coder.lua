local ignored_files = require("codetyper.adapters.nvim.autocmds.ignored_files")
local is_in_ignored_directory = require("codetyper.adapters.nvim.autocmds.is_in_ignored_directory")

--- Check if a file should be ignored for coder companion creation
---@param filepath string Full file path
---@return boolean
local function should_ignore_for_coder(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t")

  for _, ignored in ipairs(ignored_files) do
    if filename == ignored then
      return true
    end
  end

  if filename:match("^%.") then
    return true
  end

  if is_in_ignored_directory(filepath) then
    return true
  end

  return false
end

return should_ignore_for_coder
