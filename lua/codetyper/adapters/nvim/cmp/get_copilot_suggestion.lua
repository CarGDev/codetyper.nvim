--- Try to get Copilot suggestion if plugin is installed
---@param prefix string
---@return string|nil suggestion
local function get_copilot_suggestion(prefix)
  -- Try copilot.lua suggestion API first
  local ok, copilot_suggestion = pcall(require, "copilot.suggestion")
  if ok and copilot_suggestion and type(copilot_suggestion.get_suggestion) == "function" then
    local ok2, suggestion = pcall(copilot_suggestion.get_suggestion)
    if ok2 and suggestion and suggestion ~= "" then
      if prefix == "" or suggestion:lower():match(prefix:lower(), 1) then
        return suggestion
      else
        return suggestion
      end
    end
  end

  -- Fallback: try older copilot module if present
  local ok3, copilot = pcall(require, "copilot")
  if ok3 and copilot and type(copilot.get_suggestion) == "function" then
    local ok4, suggestion = pcall(copilot.get_suggestion)
    if ok4 and suggestion and suggestion ~= "" then
      return suggestion
    end
  end

  return nil
end

return get_copilot_suggestion
