local utils = require("codetyper.support.utils")

--- Update brain with patterns from a file
---@param filepath string
local function update_brain_from_file(filepath)
  local brain_loaded, brain = pcall(require, "codetyper.brain")
  if not brain_loaded or not brain.is_initialized() then
    return
  end

  local content = utils.read_file(filepath)
  if not content or content == "" then
    return
  end

  local ext = vim.fn.fnamemodify(filepath, ":e")
  local lines = vim.split(content, "\n")

  local functions = {}
  local classes = {}
  local imports = {}

  for line_index, line in ipairs(lines) do
    local func_name = line:match("^%s*function%s+([%w_:%.]+)%s*%(")
      or line:match("^%s*local%s+function%s+([%w_]+)%s*%(")
      or line:match("^%s*def%s+([%w_]+)%s*%(")
      or line:match("^%s*func%s+([%w_]+)%s*%(")
      or line:match("^%s*async%s+function%s+([%w_]+)%s*%(")
      or line:match("^%s*public%s+.*%s+([%w_]+)%s*%(")
      or line:match("^%s*private%s+.*%s+([%w_]+)%s*%(")
    if func_name then
      table.insert(functions, { name = func_name, line = line_index })
    end

    local class_name = line:match("^%s*class%s+([%w_]+)")
      or line:match("^%s*public%s+class%s+([%w_]+)")
      or line:match("^%s*interface%s+([%w_]+)")
      or line:match("^%s*struct%s+([%w_]+)")
    if class_name then
      table.insert(classes, { name = class_name, line = line_index })
    end

    local import_path = line:match("import%s+.*%s+from%s+[\"']([^\"']+)[\"']")
      or line:match("require%([\"']([^\"']+)[\"']%)")
      or line:match("from%s+([%w_.]+)%s+import")
    if import_path then
      table.insert(imports, import_path)
    end
  end

  if #functions == 0 and #classes == 0 then
    return
  end

  local parts = {}
  if #functions > 0 then
    local func_names = {}
    for func_index, func_entry in ipairs(functions) do
      if func_index <= 5 then
        table.insert(func_names, func_entry.name)
      end
    end
    table.insert(parts, "functions: " .. table.concat(func_names, ", "))
  end
  if #classes > 0 then
    local class_names = {}
    for _, class_entry in ipairs(classes) do
      table.insert(class_names, class_entry.name)
    end
    table.insert(parts, "classes: " .. table.concat(class_names, ", "))
  end

  local summary = vim.fn.fnamemodify(filepath, ":t") .. " - " .. table.concat(parts, "; ")

  brain.learn({
    type = "pattern_detected",
    file = filepath,
    timestamp = os.time(),
    data = {
      name = summary,
      description = #functions .. " functions, " .. #classes .. " classes",
      language = ext,
      symbols = vim.tbl_map(function(func_entry)
        return func_entry.name
      end, functions),
      example = nil,
    },
  })
end

return update_brain_from_file
