--- Get completion items from current buffer (fallback)
---@param prefix string Current word prefix
---@param bufnr number Buffer number
---@return table[] items
local function get_buffer_completions(prefix, bufnr)
  local items = {}
  local seen = {}

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local prefix_lower = prefix:lower()

  for _, line in ipairs(lines) do
    for word in line:gmatch("[%a_][%w_]*") do
      if #word >= 3 and word:lower():find(prefix_lower, 1, true) and not seen[word] and word ~= prefix then
        seen[word] = true
        table.insert(items, {
          label = word,
          kind = 1, -- Text
          detail = "[buffer]",
        })
      end
    end
  end

  return items
end

return get_buffer_completions
