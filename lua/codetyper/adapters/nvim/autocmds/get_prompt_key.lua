--- Generate a unique key for a prompt
---@param bufnr number Buffer number
---@param prompt table Prompt object
---@return string Unique key
local function get_prompt_key(bufnr, prompt)
  return string.format("%d:%d:%d:%s", bufnr, prompt.start_line, prompt.end_line, prompt.content:sub(1, 50))
end

return get_prompt_key
