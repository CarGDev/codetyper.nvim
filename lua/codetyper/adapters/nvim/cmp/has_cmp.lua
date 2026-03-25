--- Check if cmp is available
---@return boolean
local function has_cmp()
  return pcall(require, "cmp")
end

return has_cmp
