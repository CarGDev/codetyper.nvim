local utils = require("codetyper.support.utils")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Update brain with patterns and coding style from a saved file
---@param filepath string
local function update_brain_from_file(filepath)
  local brain_loaded, brain = pcall(require, "codetyper.core.memory")
  if not brain_loaded or not brain.is_initialized() then
    return
  end

  local content = utils.read_file(filepath)
  if not content or content == "" then
    return
  end

  local ext = vim.fn.fnamemodify(filepath, ":e")
  local filename = vim.fn.fnamemodify(filepath, ":t")
  local lines = vim.split(content, "\n")

  -- Extract functions and classes (structure analysis)
  local functions = {}
  local classes = {}
  local imports = {}

  for line_index, line in ipairs(lines) do
    local func_name = line:match("^%s*function%s+([%w_:%.]+)%s*%(")
      or line:match("^%s*local%s+function%s+([%w_]+)%s*%(")
      or line:match("^%s*def%s+([%w_]+)%s*%(")
      or line:match("^%s*func%s+([%w_]+)%s*%(")
    if func_name then
      table.insert(functions, { name = func_name, line = line_index })
    end

    local class_name = line:match("^%s*class%s+([%w_]+)")
      or line:match("^%s*struct%s+([%w_]+)")
    if class_name then
      table.insert(classes, { name = class_name, line = line_index })
    end

    local import_path = line:match("require%([\"']([^\"']+)[\"']%)")
      or line:match("import%s+.*from%s+[\"']([^\"']+)[\"']")
    if import_path then
      table.insert(imports, import_path)
    end
  end

  -- Analyze coding style
  local style_analyzer = require("codetyper.core.agent.style_analyzer")
  local conventions = style_analyzer.analyze(filepath, lines)
  local style_summary = style_analyzer.summarize(conventions)

  -- Build structure summary
  local func_names = {}
  for i, f in ipairs(functions) do
    if i <= 8 then
      table.insert(func_names, f.name)
    end
  end

  local structure = ""
  if #func_names > 0 then
    structure = "functions: " .. table.concat(func_names, ", ")
  end
  if #classes > 0 then
    local class_names = {}
    for _, c in ipairs(classes) do
      table.insert(class_names, c.name)
    end
    structure = structure .. (#structure > 0 and "; " or "") .. "classes: " .. table.concat(class_names, ", ")
  end
  if #imports > 0 then
    structure = structure .. (#structure > 0 and "; " or "") .. #imports .. " imports"
  end

  -- Learn file structure + coding style
  local summary = string.format("%s (%s, %d lines)", filename, ext, #lines)
  local detail = ""
  if #structure > 0 then
    detail = structure
  end
  if #style_summary > 0 then
    detail = detail .. (#detail > 0 and "\n" or "") .. "Style: " .. style_summary
  end

  if #detail > 0 then
    brain.learn({
      type = "file_indexed",
      file = filepath,
      timestamp = os.time(),
      data = {
        name = summary,
        description = detail,
        language = ext,
        symbols = func_names,
        conventions = conventions,
      },
    })
    flog.info("brain_update", string.format("learned from %s: %s", filename, detail:sub(1, 100))) -- TODO: remove after debugging
  end
end

return update_brain_from_file
