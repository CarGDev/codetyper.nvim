--- Get completion items from brain context
---@param prefix string Current word prefix
---@return table[] items
local function get_brain_completions(prefix)
  local items = {}

  local ok_brain, brain = pcall(require, "codetyper.brain")
  if not ok_brain then
    return items
  end

  -- Check if brain is initialized safely
  local is_init = false
  if brain.is_initialized then
    local ok, result = pcall(brain.is_initialized)
    is_init = ok and result
  end

  if not is_init then
    return items
  end

  -- Query brain for relevant patterns
  local ok_query, result = pcall(brain.query, {
    query = prefix,
    max_results = 10,
    types = { "pattern" },
  })

  if ok_query and result and result.nodes then
    for _, node in ipairs(result.nodes) do
      if node.c and node.c.s then
        local summary = node.c.s
        for name in summary:gmatch("functions:%s*([^;]+)") do
          for func in name:gmatch("([%w_]+)") do
            if func:lower():find(prefix:lower(), 1, true) then
              table.insert(items, {
                label = func,
                kind = 3, -- Function
                detail = "[brain]",
                documentation = summary,
              })
            end
          end
        end
        for name in summary:gmatch("classes:%s*([^;]+)") do
          for class in name:gmatch("([%w_]+)") do
            if class:lower():find(prefix:lower(), 1, true) then
              table.insert(items, {
                label = class,
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
