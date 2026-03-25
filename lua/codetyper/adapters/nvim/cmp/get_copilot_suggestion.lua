--- Try to get Copilot suggestion if plugin is installed
---@param prefix string
---@return string|nil suggestion
local function get_copilot_suggestion(prefix)
  local suggestion_api_loaded, copilot_suggestion_api = pcall(require, "copilot.suggestion")
  if suggestion_api_loaded and copilot_suggestion_api and type(copilot_suggestion_api.get_suggestion) == "function" then
    local suggestion_fetch_success, suggestion = pcall(copilot_suggestion_api.get_suggestion)
    if suggestion_fetch_success and suggestion and suggestion ~= "" then
      return suggestion
    end
  end

  local copilot_loaded, copilot = pcall(require, "copilot")
  if copilot_loaded and copilot and type(copilot.get_suggestion) == "function" then
    local suggestion_fetch_success, suggestion = pcall(copilot.get_suggestion)
    if suggestion_fetch_success and suggestion and suggestion ~= "" then
      return suggestion
    end
  end

  return nil
end

return get_copilot_suggestion
