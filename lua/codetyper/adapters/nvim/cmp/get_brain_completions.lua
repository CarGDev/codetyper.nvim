--- Get completion items from brain context
---@param prefix string Current word prefix
---@return table[] items
local function get_brain_completions(prefix)
  local items = {}

  local brain_loaded, brain = pcall(require, "codetyper.brain")
  if not brain_loaded then
    return items
  end

  local brain_initialized = false
  if brain.is_initialized then
    local init_check_success, init_state = pcall(brain.is_initialized)
    brain_initialized = init_check_success and init_state
  end

  if not brain_initialized then
    return items
  end

  local query_success, query_result = pcall(brain.query, {
    query = prefix,
    max_results = 10,
    types = { "pattern" },
  })

  if query_success and query_result and query_result.nodes then
    for _, node in ipairs(query_result.nodes) do
      if node.c and node.c.s then
        local summary = node.c.s
        for matched_functions in summary:gmatch("functions:%s*([^;]+)") do
          for func_name in matched_functions:gmatch("([%w_]+)") do
            if func_name:lower():find(prefix:lower(), 1, true) then
              table.insert(items, {
                label = func_name,
                kind = 3, -- Function
                detail = "[brain]",
                documentation = summary,
              })
            end
          end
        end
        for matched_classes in summary:gmatch("classes:%s*([^;]+)") do
          for class_name in matched_classes:gmatch("([%w_]+)") do
            if class_name:lower():find(prefix:lower(), 1, true) then
              table.insert(items, {
                label = class_name,
                kind = 7, -- Class
                detail = "[brain]",
                documentation = summary,
              })
            end
          end
        end
      end
    end
  end

  return items
end

return get_brain_completions
