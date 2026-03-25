--- Get completion items from indexer symbols
---@param prefix string Current word prefix
---@return table[] items
local function get_indexer_completions(prefix)
  local items = {}

  local indexer_loaded, indexer = pcall(require, "codetyper.indexer")
  if not indexer_loaded then
    return items
  end

  local index_load_success, index = pcall(indexer.load_index)
  if not index_load_success or not index then
    return items
  end

  if index.symbols then
    for symbol, files in pairs(index.symbols) do
      if symbol:lower():find(prefix:lower(), 1, true) then
        local files_display = type(files) == "table" and table.concat(files, ", ") or tostring(files)
        table.insert(items, {
          label = symbol,
          kind = 6, -- Variable (generic)
          detail = "[index] " .. files_display:sub(1, 30),
          documentation = "Symbol found in: " .. files_display,
        })
      end
    end
  end

  if index.files then
    for filepath, file_index in pairs(index.files) do
      if file_index and file_index.functions then
        for _, func_entry in ipairs(file_index.functions) do
          if func_entry.name and func_entry.name:lower():find(prefix:lower(), 1, true) then
            table.insert(items, {
              label = func_entry.name,
              kind = 3, -- Function
              detail = "[index] " .. vim.fn.fnamemodify(filepath, ":t"),
              documentation = func_entry.docstring or ("Function at line " .. (func_entry.line or "?")),
            })
          end
        end
      end
      if file_index and file_index.classes then
        for _, class_entry in ipairs(file_index.classes) do
          if class_entry.name and class_entry.name:lower():find(prefix:lower(), 1, true) then
            table.insert(items, {
              label = class_entry.name,
              kind = 7, -- Class
              detail = "[index] " .. vim.fn.fnamemodify(filepath, ":t"),
              documentation = class_entry.docstring or ("Class at line " .. (class_entry.line or "?")),
            })
          end
        end
      end
    end
  end

  return items
end

return get_indexer_completions
