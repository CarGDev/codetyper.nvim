--- Pure planning and bounded application for safe import insertion.

local languages = require("codetyper.params.agents.languages")
local utils = require("codetyper.support.utils")

local M = {}

local MAX_PATH_LENGTH = 1000
local MAX_STATEMENT_LENGTH = 500
local MAX_ERROR_LENGTH = 256

local LANGUAGE_BY_EXTENSION = {
  js = "javascript",
  jsx = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  ts = "typescript",
  tsx = "typescript",
  py = "python",
  pyw = "python",
  lua = "lua",
  go = "go",
  rs = "rust",
  c = "c",
  h = "c",
  cc = "cpp",
  cp = "cpp",
  cpp = "cpp",
  cxx = "cpp",
  hh = "cpp",
  hpp = "cpp",
  hxx = "cpp",
  java = "java",
  kt = "kotlin",
  kts = "kotlin",
  rb = "ruby",
  php = "php",
}

local LANGUAGE_BY_FILETYPE = {
  javascript = "javascript",
  javascriptreact = "javascript",
  js = "javascript",
  typescript = "typescript",
  typescriptreact = "typescript",
  ts = "typescript",
  python = "python",
  py = "python",
  lua = "lua",
  go = "go",
  rust = "rust",
  c = "c",
  cpp = "cpp",
  objc = "c",
  objcpp = "cpp",
  java = "java",
  kotlin = "kotlin",
  ruby = "ruby",
  php = "php",
}

local COMMENT_LANGUAGE = {
  javascript = "javascript",
  typescript = "typescript",
  python = "python",
  lua = "lua",
  go = "go",
  rust = "rust",
  c = "c",
  cpp = "c",
  java = "java",
  kotlin = "java",
  ruby = "ruby",
  php = "php",
}

local SYNTAX_LANGUAGE = {
  javascript = "javascript",
  typescript = "javascript",
  python = "python",
  lua = "lua",
  go = "go",
  rust = "rust",
  c = "c",
  cpp = "c",
  java = "java",
  kotlin = "java",
  ruby = "ruby",
  php = "php",
}

local uv = vim.uv or vim.loop

local function trim(value)
  return (value:match("^%s*(.-)%s*$"))
end

local function bounded_error(message)
  local value = trim(tostring(message or "import request failed"))
  value = value:gsub("[%z\1-\31\127]", " ")
  if #value > MAX_ERROR_LENGTH then
    value = value:sub(1, MAX_ERROR_LENGTH)
  end
  return value
end

local function error_result(message)
  return {
    ok = false,
    status = "error",
    data = nil,
    error = bounded_error(message),
    stale = false,
    changed = false,
    imports_added = 0,
  }
end

local function is_blank(line)
  return trim(line) == ""
end

local function path_basename(path)
  return path:match("([^/]+)$") or path
end

local function normalize_root(root)
  if type(root) ~= "string" or root == "" then
    return nil, "project root is unavailable"
  end
  local absolute = vim.fn.fnamemodify(root, ":p"):gsub("/+$", "")
  if absolute == "" then
    return nil, "project root is unavailable"
  end
  return absolute
end

local function is_within_root(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function real_path(path)
  if uv and uv.fs_realpath then
    return uv.fs_realpath(path)
  end
  return vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
end

local function stat_path(path)
  if uv and uv.fs_stat then
    return uv.fs_stat(path)
  end
  if vim.fn.filereadable(path) == 1 then
    return { type = "file" }
  end
  return nil
end

local function safe_relative_path(value)
  if type(value) ~= "string" then
    return nil, "path must be a string"
  end
  local path = trim(value)
  if path == "" or #path > MAX_PATH_LENGTH then
    return nil, "path is empty or too long"
  end
  if path:find("[%z\1-\31\127]") then
    return nil, "path contains invalid control characters"
  end
  if path:sub(1, 1) == "/" or path:match("^[A-Za-z]:[/\\]") or path:sub(1, 1) == "~" then
    return nil, "path must be project-relative"
  end
  if path:find("\\", 1, true) then
    return nil, "path separators must be forward slashes"
  end
  if path:match("^%./") or path == "." or path:find("//", 1, true) then
    return nil, "path contains an unsafe segment"
  end
  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." then
      return nil, "path traversal is not allowed"
    end
  end
  if path:sub(-1) == "/" then
    return nil, "path must name a file"
  end
  return path
end

local function absolute_target(root, relative_path)
  local absolute = root .. "/" .. relative_path
  local root_real = real_path(root) or root
  local target_real = real_path(absolute)
  if target_real and root_real and not is_within_root(target_real, root_real) then
    return nil, "target is outside the project root"
  end
  if uv and uv.fs_lstat then
    local link_stat = uv.fs_lstat(absolute)
    if link_stat and link_stat.type == "link" then
      return nil, "symbolic-link targets are not supported"
    end
  end
  return absolute
end

local function extension(path)
  local name = path_basename(path):lower()
  return name:match("%.([%w_]+)$")
end

local function is_documentation_path(path)
  local name = path_basename(path):lower()
  local function has_prefix(prefix)
    local next_character = name:sub(#prefix + 1, #prefix + 1)
    return name == prefix or next_character == "." or next_character == "_" or next_character == "-"
  end
  return has_prefix("readme")
    or has_prefix("changelog")
    or has_prefix("contributing")
    or has_prefix("security")
    or has_prefix("requirements")
    or name == "cmakelists.txt"
    or name == "makefile"
end

local function normalize_filetype(filetype)
  if type(filetype) ~= "string" then
    return nil
  end
  local value = filetype:lower()
  return LANGUAGE_BY_FILETYPE[value]
end

local function language_for(path, filetype)
  local from_filetype = normalize_filetype(filetype)
  if from_filetype then
    return from_filetype
  end
  local ext = extension(path or "")
  return ext and LANGUAGE_BY_EXTENSION[ext] or nil
end

local function split_content(content)
  local newline = content:find("\r\n", 1, true) and "\r\n" or "\n"
  local normalized = content:gsub("\r\n", "\n"):gsub("\r", "\n")
  local trailing_newline = normalized:sub(-1) == "\n"
  if trailing_newline then
    normalized = normalized:sub(1, -2)
  end
  local lines = {}
  if normalized == "" then
    lines[1] = ""
  else
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
      table.insert(lines, line)
    end
  end
  return lines, newline, trailing_newline
end

local function join_content(lines, newline, trailing_newline)
  local content = table.concat(lines, newline)
  if trailing_newline then
    content = content .. newline
  end
  return content
end

local function lines_hash(lines)
  return vim.fn.sha256(table.concat(lines, "\n"))
end

local function file_hash(content)
  return vim.fn.sha256(content)
end

local function get_buffer_filetype(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  return vim.bo[bufnr].filetype or ""
end

local function buffer_path(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  return vim.fn.fnamemodify(name, ":p"):gsub("/+$", "")
end

local function relative_to_root(absolute, root)
  local absolute_real = real_path(absolute) or absolute
  local root_real = real_path(root) or root
  if not is_within_root(absolute_real, root_real) then
    return nil, "buffer target is outside the project root"
  end
  local relative = absolute_real:sub(#root_real + 2)
  return safe_relative_path(relative)
end

local function is_comment_line(line, language)
  local text = trim(line)
  if text == "" then
    return false
  end
  if text:sub(1, 2) == "/*" or text:sub(1, 1) == "*" or text:sub(1, 2) == "*/" then
    return true
  end
  if (language == "c" or language == "cpp") and text:sub(1, 1) == "#" then
    return false
  end
  local comment_language = COMMENT_LANGUAGE[language] or language
  local patterns = languages.comment_patterns[comment_language]
  if patterns then
    for _, pattern in ipairs(patterns) do
      if text:match(pattern) then
        return true
      end
    end
  end
  if comment_language == "python" or comment_language == "ruby" or comment_language == "c" then
    return text:sub(1, 1) == "#"
  end
  if comment_language == "lua" then
    return text:sub(1, 2) == "--"
  end
  return false
end

local function consume_block_comment(lines, index)
  local line = lines[index]
  if not trim(line):match("^/%*") or line:find("*/", 3, true) then
    return index
  end
  local current = index + 1
  while current <= #lines do
    if lines[current]:find("*/", 1, true) then
      return current
    end
    current = current + 1
  end
  return #lines
end

local function consume_docstring(lines, index)
  local text = trim(lines[index])
  local delimiter
  if text:sub(1, 3) == '"""' then
    delimiter = '"""'
  elseif text:sub(1, 3) == "'''" then
    delimiter = "'''"
  end
  if not delimiter then
    return nil
  end
  if text:find(delimiter, #delimiter + 1, true) then
    return index
  end
  local current = index + 1
  while current <= #lines do
    if lines[current]:find(delimiter, 1, true) then
      return current
    end
    current = current + 1
  end
  return nil, "unterminated Python module documentation"
end

local function is_shebang(line)
  return trim(line):sub(1, 2) == "#!"
end

local function is_metadata_line(line, language, index, lines)
  local text = trim(line)
  if text == "" or is_comment_line(line, language) then
    return true
  end
  if index == 1 and is_shebang(line) then
    return true
  end
  if language == "python" and (text:match("^#.*coding[:=]") or text:match("^#.*vim:")) then
    return true
  end
  if language == "javascript" or language == "typescript" then
    return text:match("^['\"]use[%w_]+['\"]%s*;?$") ~= nil
  end
  if language == "rust" then
    return text:match("^#!%[") ~= nil
  end
  if language == "go" then
    return text:match("^package%s+[%a_][%w_]*%s*$") ~= nil
  end
  if language == "java" or language == "kotlin" then
    return text:match("^package%s+[%a_$][%w_$%.]*%s*;?$") ~= nil
  end
  if language == "c" or language == "cpp" then
    if text:match("^#pragma%s+once%s*$") then
      return true
    end
    if index <= 2 and text:match("^#ifndef%s+") then
      return true
    end
    if index <= 3 and text:match("^#define%s+") then
      return true
    end
  end
  if language == "php" then
    return text:match("^<%?php%s*$") ~= nil or text:match("^declare%s*%(") ~= nil or text:match("^namespace%s+") ~= nil
  end
  return false
end

local function header_end(lines, language)
  local index = 1
  while index <= #lines do
    local line = lines[index]
    local text = trim(line)
    local is_python_docstring = language == "python" and (text:sub(1, 3) == '"""' or text:sub(1, 3) == "'''")
    if is_python_docstring then
      local end_index, doc_error = consume_docstring(lines, index)
      if not end_index then
        return #lines, doc_error
      end
      index = end_index + 1
    elseif text == "" or is_metadata_line(line, language, index, lines) then
      if trim(line):match("^/%*") then
        index = consume_block_comment(lines, index) + 1
      else
        index = index + 1
      end
    else
      break
    end
  end
  return index - 1
end

local function balanced_single_line(value)
  local stack = {}
  local quote = nil
  local escaped = false
  for index = 1, #value do
    local char = value:sub(index, index)
    if quote then
      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif char == quote then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "(" or char == "[" or char == "{" then
      table.insert(stack, char)
    elseif char == ")" or char == "]" or char == "}" then
      local expected = ({ [")"] = "(", ["]"] = "[", ["}"] = "{" })[char]
      if stack[#stack] ~= expected then
        return false
      end
      table.remove(stack)
    end
  end
  return quote == nil and #stack == 0
end

local function without_trailing_semicolon(value)
  return trim(value:gsub(";%s*$", ""))
end

local function quoted_value(value)
  return value:match('^"([^"]+)"$') or value:match("^'([^']+)'$")
end

local function valid_identifier(value)
  return value:match("^[%a_][%w_]*$") ~= nil
end

local function valid_dotted_identifier(value)
  if value == "" then
    return false
  end
  for part in value:gmatch("[^%.]+") do
    if not valid_identifier(part) then
      return false
    end
  end
  return value:sub(1, 1) ~= "." and value:sub(-1) ~= "."
end

local function valid_python_import(value)
  local text = without_trailing_semicolon(value)
  local imported = text:match("^import%s+(.+)$")
  if imported then
    if imported:find("[();#]", 1) then
      return false
    end
    for item in imported:gmatch("[^,]+") do
      local name = trim(item):match("^([%a_][%w_%.]*)%s*$")
        or trim(item):match("^([%a_][%w_%.]*)%s+as%s+([%a_][%w_]*)$")
      if not name or not valid_dotted_identifier(name) then
        local module_name = trim(item):match("^([%a_][%w_%.]*)%s+as%s+[%a_][%w_]*$")
        if not module_name or not valid_dotted_identifier(module_name) then
          return false
        end
      end
    end
    return true
  end
  local module_name, names = text:match("^from%s+([%.]*[%a_][%w_%.]*)%s+import%s+(.+)$")
  if not module_name or not names or names == "" or names:find("[();#]", 1) then
    return false
  end
  for item in names:gmatch("[^,]+") do
    local name = trim(item)
    if name ~= "*" and not valid_identifier(name) and not name:match("^[%a_][%w_]*%s+as%s+[%a_][%w_]*$") then
      return false
    end
  end
  return true
end

local function valid_javascript_import(value)
  local text = trim(value)
  local without_semicolon = without_trailing_semicolon(text)
  local side_effect = without_semicolon:match('^import%s+"([^"]+)"$') or without_semicolon:match("^import%s+'([^']+)'$")
  if side_effect and side_effect ~= "" then
    return true
  end
  local from_bindings = without_semicolon:match('^import%s+(.+)%s+from%s+"([^"]+)"$')
    or without_semicolon:match("^import%s+(.+)%s+from%s+'([^']+)'$")
  if from_bindings and not from_bindings:find("[;()]", 1) and not from_bindings:find("//", 1, true) then
    return balanced_single_line(without_semicolon)
  end
  local export_bindings = without_semicolon:match('^export%s+(.+)%s+from%s+"([^"]+)"$')
    or without_semicolon:match("^export%s+(.+)%s+from%s+'([^']+)'$")
  if export_bindings and not export_bindings:find("[;()]", 1) and not export_bindings:find("//", 1, true) then
    return balanced_single_line(without_semicolon)
  end
  local require_source = without_semicolon:match('^require%s*%(%s*"([^"]+)"%s*%)$')
    or without_semicolon:match("^require%s*%(%s*'([^']+)'%s*%)$")
  if require_source then
    return true
  end
  local variable_require = without_semicolon:match('^const%s+[%a_$][%w_$]*%s*=%s*require%s*%(%s*"([^"]+)"%s*%)$')
    or without_semicolon:match("^const%s+[%a_$][%w_$]*%s*=%s*require%s*%(%s*'([^']+)'%s*%)$")
    or without_semicolon:match('^let%s+[%a_$][%w_$]*%s*=%s*require%s*%(%s*"([^"]+)"%s*%)$')
    or without_semicolon:match("^let%s+[%a_$][%w_$]*%s*=%s*require%s*%(%s*'([^']+)'%s*%)$")
    or without_semicolon:match('^var%s+[%a_$][%w_$]*%s*=%s*require%s*%(%s*"([^"]+)"%s*%)$')
    or without_semicolon:match("^var%s+[%a_$][%w_$]*%s*=%s*require%s*%(%s*'([^']+)'%s*%)$")
  return variable_require ~= nil
end

local function valid_lua_import(value)
  local text = without_trailing_semicolon(value)
  local module_name = text:match('^require%s*%(%s*"([^"]+)"%s*%)$')
    or text:match("^require%s*%(%s*'([^']+)'%s*%)$")
    or text:match('^require%s+"([^"]+)"$')
    or text:match("^require%s+'([^']+)'$")
    or text:match('^local%s+[%a_][%w_]*%s*=%s*require%s*%(%s*"([^"]+)"%s*%)$')
    or text:match("^local%s+[%a_][%w_]*%s*=%s*require%s*%(%s*'([^']+)'%s*%)$")
  return module_name ~= nil and module_name ~= ""
end

local function valid_go_import(value)
  local text = without_trailing_semicolon(value)
  if text:match("^import%s*%(") then
    return false
  end
  if text:match('^import%s+"([^"]+)"$') then
    return true
  end
  if text:match('^import%s+[%a_][%w_]*%s+"([^"]+)"$') then
    return true
  end
  return text:match('^import%s+[._]%s+"([^"]+)"$') ~= nil
end

local function valid_rust_import(value)
  local text = without_trailing_semicolon(value)
  if text:match("^extern%s+crate%s+") then
    return text:match("^extern%s+crate%s+[%a_][%w_]*$") ~= nil
  end
  if not text:match("^use%s+") or text:find("=", 1, true) then
    return false
  end
  return balanced_single_line(text) and text:match("^use%s+[%a_][%w_:{}*,%s]*$") ~= nil
end

local function valid_c_import(value)
  return trim(value):match("^#include%s+<[^>\r\n]+>$") ~= nil or trim(value):match('^#include%s+"[^"\r\n]+"$') ~= nil
end

local function valid_java_import(value)
  local text = without_trailing_semicolon(value)
  if not text:match("^import%s+") then
    return false
  end
  local path = text:match("^import%s+([%a_$][%w_$%.]*%*?)$")
  if not path then
    path = text:match("^import%s+([%a_$][%w_$%.]*)%s+as%s+[%a_$][%w_$]*$")
  end
  return path ~= nil
end

local function valid_ruby_import(value)
  local text = without_trailing_semicolon(value)
  local module_name = text:match('^require%s+"([^"]+)"$')
    or text:match("^require%s+'([^']+)'$")
    or text:match('^require_relative%s+"([^"]+)"$')
    or text:match("^require_relative%s+'([^']+)'$")
  return module_name ~= nil and module_name ~= ""
end

local function valid_php_import(value)
  local text = without_trailing_semicolon(value)
  if text:match("^use%s+") then
    local body = text:match("^use%s+(.+)$")
    if not body or body:find("[();=]", 1) or body:find("//", 1, true) or body:find("/*", 1, true) then
      return false
    end
    local function valid_character(character)
      return character:match("[%a%d_]") ~= nil or character == "\\" or character == " "
    end
    for character in body:gmatch(".") do
      if not valid_character(character) then
        return false
      end
    end
    return body:match("^[%a_][%w_\\]*$") ~= nil or body:match("^[%a_][%w_\\]*%s+as%s+[%a_][%w_]*$") ~= nil
  end
  local module_name = text:match('^require%s+"([^"]+)"$')
    or text:match("^require%s+'([^']+)'$")
    or text:match('^require_once%s+"([^"]+)"$')
    or text:match("^require_once%s+'([^']+)'$")
    or text:match('^include%s+"([^"]+)"$')
    or text:match("^include%s+'([^']+)'$")
    or text:match('^include_once%s+"([^"]+)"$')
    or text:match("^include_once%s+'([^']+)'$")
  return module_name ~= nil and module_name ~= ""
end

local function unsafe_reference(value)
  if value == "" then
    return true
  end
  if value:match("^[A-Za-z]:[/\\]") or value:sub(1, 1) == "/" or value:sub(1, 1) == "~" then
    return true
  end
  if value:find("://", 1, true) or value:find("../", 1, true) or value:find("\\..\\", 1, true) then
    return true
  end
  return false
end

local function has_unsafe_references(statement, language)
  if language == "python" and statement:match("^from%s+%.%.") then
    return true
  end
  for value in statement:gmatch('"([^"]*)"') do
    if unsafe_reference(value) then
      return true
    end
  end
  for value in statement:gmatch("'([^']*)'") do
    if unsafe_reference(value) then
      return true
    end
  end
  for value in statement:gmatch("<([^>]+)>") do
    if unsafe_reference(value) then
      return true
    end
  end
  return false
end

local VALIDATORS = {
  javascript = valid_javascript_import,
  typescript = valid_javascript_import,
  python = valid_python_import,
  lua = valid_lua_import,
  go = valid_go_import,
  rust = valid_rust_import,
  c = valid_c_import,
  cpp = valid_c_import,
  java = valid_java_import,
  kotlin = valid_java_import,
  ruby = valid_ruby_import,
  php = valid_php_import,
}

local function validate_statement(statement, language)
  if type(statement) ~= "string" then
    return nil, "statement must be a string"
  end
  local value = trim(statement)
  if value == "" or #value > MAX_STATEMENT_LENGTH then
    return nil, "statement is empty or too long"
  end
  if value:find("[\r\n]") or value:find("[%z\1-\31\127]") then
    return nil, "statement must be a safe single line"
  end
  if value:find("/%*") or value:find("%*/") then
    return nil, "comments are not allowed in import statements"
  end
  if value:find("//", 1, true) and language ~= "javascript" and language ~= "typescript" then
    return nil, "comments are not allowed in import statements"
  end
  if has_unsafe_references(value, language) then
    return nil, "module reference is outside the safe project boundary"
  end
  if not balanced_single_line(value) then
    return nil, "statement has unbalanced delimiters"
  end
  local validator = VALIDATORS[language]
  if not validator or not validator(value) then
    return nil, "statement is not a complete supported import declaration"
  end
  return value
end

local function is_import_start(line, language)
  local text = trim(line)
  if text == "" or is_comment_line(line, language) then
    return false
  end
  if language == "javascript" or language == "typescript" then
    return text:match("^import%s") ~= nil
      or text:match("^export%s+[%{%*]") ~= nil
      or text:match("^(const|let|var)%s+[%a_$]") ~= nil and text:find("require", 1, true) ~= nil
      or text:match("^require%s*%(") ~= nil
  elseif language == "python" then
    return text:match("^import%s") ~= nil or text:match("^from%s") ~= nil
  elseif language == "lua" then
    return text:match("^require%s") ~= nil or text:match("^local%s+[%a_][%w_]*%s*=%s*require") ~= nil
  elseif language == "go" then
    return text:match("^import%s") ~= nil
  elseif language == "rust" then
    return text:match("^use%s") ~= nil or text:match("^extern%s+crate%s") ~= nil
  elseif language == "c" or language == "cpp" then
    return text:match("^#include%s") ~= nil
  elseif language == "java" or language == "kotlin" then
    return text:match("^import%s") ~= nil
  elseif language == "ruby" then
    return text:match("^require%s") ~= nil or text:match("^require_relative%s") ~= nil
  elseif language == "php" then
    return text:match("^use%s") ~= nil
      or text:match("^require%s") ~= nil
      or text:match("^require_once%s") ~= nil
      or text:match("^include%s") ~= nil
      or text:match("^include_once%s") ~= nil
  end
  local patterns = languages.import_patterns[SYNTAX_LANGUAGE[language] or language]
  if patterns then
    for _, definition in ipairs(patterns) do
      if text:match(definition.pattern) then
        return true
      end
    end
  end
  return false
end

local function canonical_statement(statement)
  local value = trim(statement):gsub(";%s*$", "")
  value = value:gsub("%s*([{}%(%),=])%s*", "%1")
  value = value:gsub("%s+", " ")
  value = value:gsub("'", '"')
  return value
end

local function go_item_statement(item)
  local value = trim(item)
  if value == "" then
    return nil
  end
  if value:sub(1, 1) == '"' or value:sub(1, 1) == "." or value:sub(1, 1) == "_" then
    return "import " .. value
  end
  local alias, path = value:match('^([%a_][%w_]*)%s+("[^"]+")$')
  if alias and path then
    return "import " .. alias .. " " .. path
  end
  return nil
end

local function parse_import_unit(lines, index, language)
  local line = lines[index]
  if not is_import_start(line, language) then
    return nil
  end
  local text = trim(line)
  if (language == "go") and text:match("^import%s*%(%s*$") then
    local finish = index + 1
    while finish <= #lines and not trim(lines[finish]):match("^%)%s*$") do
      finish = finish + 1
    end
    if finish > #lines then
      return { start = index, finish = #lines, ambiguous = true }
    end
    local keys = {}
    for item_index = index + 1, finish - 1 do
      local item = trim(lines[item_index])
      if item ~= "" and not is_comment_line(item, language) then
        local item_statement = go_item_statement(item)
        if not item_statement then
          return { start = index, finish = finish, ambiguous = true }
        end
        table.insert(keys, canonical_statement(item_statement))
      end
    end
    return { start = index, finish = finish, keys = keys, go_group = true }
  end

  local end_index = index
  local combined = line
  while not balanced_single_line(combined) and end_index < #lines do
    end_index = end_index + 1
    combined = combined .. "\n" .. lines[end_index]
  end
  if not balanced_single_line(combined) then
    return { start = index, finish = end_index, ambiguous = true }
  end
  if end_index ~= index then
    return { start = index, finish = end_index, keys = { canonical_statement(combined) }, multiline = true }
  end
  local valid = validate_statement(text, language)
  if not valid then
    return { start = index, finish = index, malformed = true }
  end
  return { start = index, finish = index, keys = { canonical_statement(valid) } }
end

local function collect_imports(lines, language)
  local keys = {}
  local index = 1
  while index <= #lines do
    local unit = parse_import_unit(lines, index, language)
    if unit then
      if unit.ambiguous then
        return nil, "existing import block is ambiguous"
      end
      if unit.malformed then
        return nil, "existing import declaration is malformed"
      end
      for _, key in ipairs(unit.keys or {}) do
        keys[key] = true
      end
      index = unit.finish + 1
    else
      index = index + 1
    end
  end
  return keys
end

local function find_import_region(lines, language, header_count)
  local first_import = nil
  local last_import = nil
  local group = nil
  local cursor = header_count + 1
  while cursor <= #lines do
    local unit = parse_import_unit(lines, cursor, language)
    if unit then
      if unit.ambiguous or unit.malformed then
        return nil, "existing import block is ambiguous"
      end
      first_import = first_import or unit.start
      last_import = unit.finish
      if unit.go_group then
        group = unit
      end
      cursor = unit.finish + 1
    elseif is_blank(lines[cursor]) or is_comment_line(lines[cursor], language) then
      local probe = cursor + 1
      while probe <= #lines and (is_blank(lines[probe]) or is_comment_line(lines[probe], language)) do
        probe = probe + 1
      end
      if probe <= #lines and parse_import_unit(lines, probe, language) then
        cursor = probe
      else
        break
      end
    else
      break
    end
  end
  return {
    first = first_import,
    last = last_import,
    group = group,
    insert_at = last_import and (last_import + 1) or (header_count + 1),
  }
end

local function resolve_target(input, language)
  local root, root_error = normalize_root(input.root or utils.get_project_root())
  if not root then
    return nil, root_error
  end

  local bufnr = input.bufnr
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local relative_path = input.path
  local path_error
  if relative_path ~= nil then
    relative_path, path_error = safe_relative_path(relative_path)
    if not relative_path then
      return nil, path_error
    end
  elseif bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local absolute = buffer_path(bufnr)
    if not absolute then
      return nil, "open buffer has no project-relative path"
    end
    relative_path, path_error = relative_to_root(absolute, root)
    if not relative_path then
      return nil, path_error
    end
  else
    return nil, "path is required"
  end

  local absolute, absolute_error = absolute_target(root, relative_path)
  if not absolute then
    return nil, absolute_error
  end

  if not bufnr then
    local named_buffer = vim.fn.bufnr(absolute)
    if named_buffer ~= -1 and vim.api.nvim_buf_is_valid(named_buffer) and vim.api.nvim_buf_is_loaded(named_buffer) then
      bufnr = named_buffer
    end
  end

  local actual_language = language or language_for(relative_path, input.filetype)
  if not actual_language then
    return nil, "target language is unsupported"
  end

  if type(input.lines) == "table" then
    local lines = vim.deepcopy(input.lines)
    return {
      kind = input.target_kind or "memory",
      bufnr = bufnr,
      absolute_path = absolute,
      relative_path = relative_path,
      lines = lines,
      newline = "\n",
      trailing_newline = false,
      expected_hash = lines_hash(lines),
      language = actual_language,
    }
  end

  if type(input.content) == "string" then
    local lines, newline, trailing_newline = split_content(input.content)
    return {
      kind = input.target_kind or "memory",
      bufnr = bufnr,
      absolute_path = absolute,
      relative_path = relative_path,
      lines = lines,
      newline = newline,
      trailing_newline = trailing_newline,
      expected_hash = file_hash(input.content),
      language = actual_language,
    }
  end

  local named_buffer_path = buffer_path(bufnr)
  local same_named_path = named_buffer_path == absolute
  if named_buffer_path and not same_named_path then
    same_named_path = (real_path(named_buffer_path) or named_buffer_path) == (real_path(absolute) or absolute)
  end
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and same_named_path then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return {
      kind = "buffer",
      bufnr = bufnr,
      absolute_path = named_buffer_path,
      relative_path = relative_path,
      lines = lines,
      newline = "\n",
      trailing_newline = false,
      expected_hash = lines_hash(lines),
      language = actual_language,
    }
  end

  local stat = stat_path(absolute)
  if not stat or stat.type ~= "file" then
    return nil, "target file does not exist"
  end
  local file, open_error = io.open(absolute, "rb")
  if not file then
    return nil, "target file cannot be read"
  end
  local content = file:read("*all")
  file:close()
  local lines, newline, trailing_newline = split_content(content)
  return {
    kind = "file",
    bufnr = nil,
    absolute_path = absolute,
    relative_path = relative_path,
    lines = lines,
    newline = newline,
    trailing_newline = trailing_newline,
    expected_hash = file_hash(content),
    language = actual_language,
  }
end

local function format_go_group_item(statement, lines, group)
  local item = trim(statement:gsub("^import%s+", ""))
  local indent = "\t"
  for index = group.start + 1, group.finish - 1 do
    local existing = lines[index]
    if trim(existing) ~= "" and not is_comment_line(existing, "go") then
      indent = existing:match("^(%s*)") or indent
      break
    end
  end
  return indent .. item
end

local function target_result(plan, action, imports_added)
  return {
    ok = true,
    status = action == "noop" and "noop" or "planned",
    action = action,
    changed = action ~= "noop",
    imports_added = imports_added,
    statement = plan.statement,
    language = plan.language,
    path = plan.relative_path,
    insert_at = plan.insert_at,
    lines = plan.lines,
  }
end

--- Return the canonical language for a path or filetype.
---@param path string|nil Project-relative path
---@param filetype string|nil Neovim filetype
---@return string|nil language
function M.language_for(path, filetype)
  return language_for(path or "", filetype)
end

--- Validate and plan one deterministic import without mutating a target.
---@param input table {root,path,statement,content,lines,bufnr,filetype}
---@return table|nil plan
---@return string|nil error
function M.plan(input)
  if type(input) ~= "table" then
    return nil, "import input must be an object"
  end
  local requested_path = input.path
  if not requested_path and input.bufnr and vim.api.nvim_buf_is_valid(input.bufnr) then
    requested_path = buffer_path(input.bufnr)
  end
  if requested_path and is_documentation_path(requested_path) then
    return nil, "target is not a code file"
  end
  local requested_language = language_for(input.path or "", input.filetype)
  if not requested_language and input.bufnr and vim.api.nvim_buf_is_valid(input.bufnr) then
    requested_language = language_for(buffer_path(input.bufnr) or "", get_buffer_filetype(input.bufnr))
  end
  if not requested_language then
    return nil, "target language is unsupported"
  end
  local statement, statement_error = validate_statement(input.statement, requested_language)
  if not statement then
    return nil, statement_error
  end
  local target, target_error = resolve_target(input, requested_language)
  if not target then
    return nil, target_error
  end
  local header_count, header_error = header_end(target.lines, target.language)
  if header_error then
    return nil, header_error
  end
  local existing_keys, existing_error = collect_imports(target.lines, target.language)
  if not existing_keys then
    return nil, existing_error
  end
  local candidate_key = canonical_statement(statement)
  if target.language == "go" and target.language then
    candidate_key = canonical_statement(statement)
  end
  if existing_keys[candidate_key] then
    local plan = {
      ok = true,
      status = "noop",
      action = "noop",
      changed = false,
      imports_added = 0,
      statement = statement,
      language = target.language,
      relative_path = target.relative_path,
      path = target.relative_path,
      lines = vim.deepcopy(target.lines),
      insert_at = nil,
      _target = target,
    }
    return plan
  end

  local region, region_error = find_import_region(target.lines, target.language, header_count)
  if not region then
    return nil, region_error
  end
  local new_lines = vim.deepcopy(target.lines)
  local insert_at = region.insert_at
  local inserted_statement = statement
  if target.language == "go" and region.group then
    inserted_statement = format_go_group_item(statement, target.lines, region.group)
    local group_item_key = canonical_statement("import " .. trim(statement:gsub("^import%s+", "")))
    if existing_keys[group_item_key] then
      local plan = {
        ok = true,
        status = "noop",
        action = "noop",
        changed = false,
        imports_added = 0,
        statement = statement,
        language = target.language,
        relative_path = target.relative_path,
        path = target.relative_path,
        lines = vim.deepcopy(target.lines),
        insert_at = nil,
        _target = target,
      }
      return plan
    end
    insert_at = region.group.finish
  end
  table.insert(new_lines, insert_at, inserted_statement)
  local plan = {
    ok = true,
    status = "planned",
    action = "insert",
    changed = true,
    imports_added = 1,
    statement = statement,
    language = target.language,
    relative_path = target.relative_path,
    path = target.relative_path,
    lines = new_lines,
    insert_at = insert_at,
    inserted_line = inserted_statement,
    _target = target,
  }
  return plan
end

local function same_target_content(target, lines)
  if target.kind == "buffer" then
    return lines_hash(vim.api.nvim_buf_get_lines(target.bufnr, 0, -1, false)) == target.expected_hash
  end
  if target.kind == "file" then
    local file = io.open(target.absolute_path, "rb")
    if not file then
      return false
    end
    local content = file:read("*all")
    file:close()
    return file_hash(content) == target.expected_hash
  end
  return true
end

local function atomic_write(target, content)
  local temporary = string.format("%s.codetyper.tmp.%d.%d", target.absolute_path, os.time(), math.random(0, 0xFFFF))
  local file = io.open(temporary, "wb")
  if not file then
    return nil, "target file cannot be staged"
  end
  local ok = pcall(function()
    local wrote, write_error = file:write(content)
    if not wrote then
      error(write_error or "write failed")
    end
    file:flush()
    file:close()
  end)
  if not ok then
    pcall(function()
      file:close()
    end)
    os.remove(temporary)
    return nil, "target file cannot be staged"
  end
  if not os.rename(temporary, target.absolute_path) then
    os.remove(temporary)
    return nil, "target file cannot be replaced"
  end
  return true
end

--- Apply a previously generated plan with stale-target and root checks.
---@param plan table Result from M.plan
---@return table|nil result
---@return string|nil error
function M.apply(plan)
  if type(plan) ~= "table" or not plan.ok then
    return nil, "invalid import plan"
  end
  if plan.status == "noop" then
    return { ok = true, status = "noop", action = "noop", changed = false, imports_added = 0, path = plan.path }
  end
  local target = plan._target
  if not target or target.kind == "memory" then
    return nil, "plan target is not writable"
  end
  if not same_target_content(target, target.lines) then
    return nil, "target changed while import was being planned"
  end
  if target.kind == "buffer" then
    if not vim.bo[target.bufnr].modifiable then
      return nil, "target buffer is not modifiable"
    end
    vim.api.nvim_buf_set_lines(target.bufnr, 0, -1, false, plan.lines)
    return {
      ok = true,
      status = "inserted",
      action = "inserted",
      changed = true,
      imports_added = plan.imports_added,
      path = plan.path,
    }
  end
  local content = join_content(plan.lines, target.newline, target.trailing_newline)
  local ok, write_error = atomic_write(target, content)
  if not ok then
    return nil, write_error
  end
  return {
    ok = true,
    status = "inserted",
    action = "inserted",
    changed = true,
    imports_added = plan.imports_added,
    path = plan.path,
  }
end

--- Extract leading single-line import declarations from generated code.
---@param code string Generated code
---@param opts table|nil {path,filetype}
---@return table|nil extraction {statements,body_lines}
---@return string|nil error
function M.extract(code, opts)
  opts = opts or {}
  if type(code) ~= "string" then
    return nil, "generated code must be a string"
  end
  local language = language_for(opts.path or "", opts.filetype)
  local lines = split_content(code)
  local code_lines = lines
  local statements = {}
  local removed = {}
  local cursor = 1
  local seen_body = false
  while cursor <= #code_lines do
    local line = code_lines[cursor]
    local unit = language and parse_import_unit(code_lines, cursor, language) or nil
    if unit and not seen_body then
      if unit.ambiguous or unit.multiline then
        return nil, "generated import declaration must be single-line"
      end
      if unit.malformed then
        return nil, "generated import declaration is malformed"
      end
      local statement = trim(code_lines[cursor])
      local valid, statement_error = validate_statement(statement, language)
      if not valid then
        return nil, statement_error
      end
      table.insert(statements, valid)
      for index = cursor, unit.finish do
        removed[index] = true
      end
      cursor = unit.finish + 1
    elseif not seen_body and (is_blank(line) or is_comment_line(line, language or "")) then
      cursor = cursor + 1
    else
      seen_body = true
      cursor = cursor + 1
    end
  end
  local body_lines = {}
  for index, line in ipairs(code_lines) do
    if not removed[index] then
      table.insert(body_lines, line)
    end
  end
  while #body_lines > 0 and body_lines[1] == "" and #statements > 0 do
    table.remove(body_lines, 1)
  end
  while #body_lines > 0 and body_lines[#body_lines] == "" and #statements > 0 do
    table.remove(body_lines)
  end
  return { statements = statements, body_lines = body_lines, language = language }, nil
end

--- Plan several imports against an in-memory line set without mutation.
---@param input table {root,path,statements,lines,bufnr,filetype}
---@return table|nil result
---@return string|nil error
function M.plan_many(input)
  if type(input) ~= "table" or type(input.statements) ~= "table" then
    return nil, "import statements must be an array"
  end
  local current_lines = vim.deepcopy(input.lines or {})
  local plans = {}
  local added = 0
  for _, statement in ipairs(input.statements) do
    local plan, plan_error = M.plan({
      root = input.root,
      path = input.path,
      filetype = input.filetype,
      statement = statement,
      lines = current_lines,
      target_kind = "memory",
    })
    if not plan then
      return nil, plan_error
    end
    table.insert(plans, plan)
    current_lines = plan.lines
    added = added + plan.imports_added
  end
  return { plans = plans, lines = current_lines, imports_added = added }, nil
end

M.plan_import = M.plan
M.build_plan = M.plan
M.apply_plan = M.apply
M.extract_imports = M.extract
M.supported_extensions = vim.deepcopy(LANGUAGE_BY_EXTENSION)

function M.insert(input)
  if type(input) == "table" and input.ok and input._target then
    return M.apply(input)
  end
  local plan, plan_error = M.plan(input)
  if not plan then
    return nil, plan_error
  end
  if plan.status == "noop" then
    return { ok = true, status = "noop", action = "noop", changed = false, imports_added = 0, path = plan.path }
  end
  return M.apply(plan)
end

M.insert_import = M.insert
M.add = M.insert

return M
