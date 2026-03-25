--- Get completion items from indexer symbols
---@param prefix string Current word prefix
---@return table[] items
local function get_indexer_completions(prefix)
  local items = {}

  local ok_indexer, indexer = pcall(require, "codetyper.indexer")
  if not ok_indexer then
    return items
  end

  local ok_load, index = pcall(indexer.load_index)
  if not ok_load or not index then
    return items
  end

  -- Search symbols
  if index.symbols then
    for symbol, files in pairs(index.symbols) do
      if symbol:lower():find(prefix:lower(), 1, true) then
        local files_str = type(files) == "table" and table.concat(files, ", ") or tostring(files)
        table.insert(items, {
          label = symbol,
          kind = 6, -- Variable (generic)
          detail = "[index] " .. files_str:sub(1, 30),
          documentation = "Symbol found in: " .. files_str,
        })
      end
    end
  end

  -- Search functions in files
  if index.files then
    for filepath, file_index in pairs(index.files) do
      if file_index and file_index.functions then
        for _, func in ipairs(file_index.functions) do
          if func.name and func.name:lower():find(prefix:lower(), 1, true) then
            table.insert(items, {
              label = func.name,
              kind = 3, -- Function
              detail = "[index] " .. vim.fn.fnamemodify(filepath, ":t"),
              documentation = func.docstring or ("Function at line " .. (func.line or "?")),
            })
          end
        end
      end
      if file_index and file_index.classes then
        for _, class in ipairs(file_index.classes) do
          if class.name and class.name:lower():find(prefix:lower(), 1, true) then
            table.insert(items, {
              label = class.name,
              kind = 7, -- Class
              detail = "[index] " .. vim.fn.fnamemodify(filepath, ":t"),
              documentation = class.docstring or ("Class at line " .. (class.line or "?")),
            })
          end
        end
      end
    end
  end

  return items
end

return get_indexer_completions
