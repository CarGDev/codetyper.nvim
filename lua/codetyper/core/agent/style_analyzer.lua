--- Code style analyzer — extracts conventions from how the user writes code
--- Runs on file save to learn coding patterns over time
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Analyze Lua-specific patterns
---@param lines string[]
---@return table conventions
local function analyze_lua(lines)
  local conv = {}
  local content = table.concat(lines, "\n")

  -- Module pattern
  if content:match("^local M = {}") or content:match("\nlocal M = {}") then
    conv.module_pattern = "M = {} / return M"
  end

  -- Import style
  local top_requires = 0
  local lazy_requires = 0
  for _, line in ipairs(lines) do
    if line:match("^local %w+ = require%(") then
      top_requires = top_requires + 1
    end
    if line:match("require%(") and not line:match("^local") then
      lazy_requires = lazy_requires + 1
    end
  end
  if top_requires > lazy_requires then
    conv.import_style = "top-level local requires"
  elseif lazy_requires > 0 then
    conv.import_style = "mix of top-level and lazy requires"
  end

  -- Error handling
  local pcall_count = select(2, content:gsub("pcall%(", ""))
  if pcall_count >= 3 then
    conv.error_handling = "heavy pcall usage"
  elseif pcall_count >= 1 then
    conv.error_handling = "selective pcall"
  end

  -- Guard clauses
  local guard_count = select(2, content:gsub("if not .+ then%s*\n%s*return", ""))
  if guard_count >= 2 then
    conv.guard_style = "early return guards"
  end

  -- Documentation
  local luadoc_count = select(2, content:gsub("%-%-%-@", ""))
  if luadoc_count >= 3 then
    conv.documentation = "uses LuaDoc/EmmyLua annotations"
  end

  -- Function style
  local local_fn = select(2, content:gsub("local function ", ""))
  local module_fn = select(2, content:gsub("function M%.", ""))
  if local_fn > module_fn then
    conv.function_style = "prefers local functions"
  elseif module_fn > 0 then
    conv.function_style = "module functions (M.name)"
  end

  -- Indent
  local two_space = 0
  local four_space = 0
  local tab_indent = 0
  for _, line in ipairs(lines) do
    if line:match("^\t") then
      tab_indent = tab_indent + 1
    elseif line:match("^    %S") then
      four_space = four_space + 1
    elseif line:match("^  %S") then
      two_space = two_space + 1
    end
  end
  if two_space > four_space and two_space > tab_indent then
    conv.indent = "2 spaces"
  elseif four_space > two_space then
    conv.indent = "4 spaces"
  elseif tab_indent > 0 then
    conv.indent = "tabs"
  end

  -- Notify style
  if content:match("vim%.notify%(") then
    conv.notify = "uses vim.notify"
  end
  if content:match("vim%.log%.levels%.") then
    conv.notify_levels = "uses log levels (INFO/WARN/ERROR)"
  end

  return conv
end

--- Analyze general patterns (any language)
---@param lines string[]
---@param filetype string
---@return table conventions
local function analyze_general(lines, filetype)
  local conv = {}
  local content = table.concat(lines, "\n")

  conv.line_count = #lines
  conv.language = filetype

  -- Max line length
  local max_len = 0
  for _, line in ipairs(lines) do
    if #line > max_len then
      max_len = #line
    end
  end
  if max_len <= 80 then
    conv.line_length = "80 cols max"
  elseif max_len <= 100 then
    conv.line_length = "100 cols max"
  elseif max_len <= 120 then
    conv.line_length = "120 cols max"
  end

  -- Trailing newline
  if lines[#lines] == "" then
    conv.trailing_newline = true
  end

  return conv
end

--- Analyze a file and return conventions
---@param filepath string Absolute path
---@param lines string[] File lines
---@return table conventions
function M.analyze(filepath, lines)
  local ext = vim.fn.fnamemodify(filepath, ":e")
  local conv = analyze_general(lines, ext)

  if ext == "lua" then
    local lua_conv = analyze_lua(lines)
    for k, v in pairs(lua_conv) do
      conv[k] = v
    end
  end

  return conv
end

--- Build a summary string from conventions table
---@param conventions table
---@return string
function M.summarize(conventions)
  local parts = {}
  for key, value in pairs(conventions) do
    if type(value) == "string" then
      table.insert(parts, key .. ": " .. value)
    elseif type(value) == "boolean" and value then
      table.insert(parts, key)
    end
  end
  table.sort(parts)
  return table.concat(parts, ", ")
end

return M
