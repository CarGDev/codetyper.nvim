local supported_extensions = require("codetyper.adapters.nvim.autocmds.supported_extensions")

--- Check if extension is supported for auto-indexing
---@param ext string File extension
---@return boolean
local function is_supported_extension(ext)
  for _, supported in ipairs(supported_extensions) do
    if ext == supported then
      return true
    end
  end
  return false
end

return is_supported_extension
